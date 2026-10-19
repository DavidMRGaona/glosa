#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 DavidMRGaona (https://github.com/DavidMRGaona)
#
# glosa: docopt-style argument parser in pure Bash (3.2+).
#
# Source it and call glosa::parse, or run it and eval its output:
#
#   source glosa.sh; glosa::parse "$help" "$@"
#   eval "$(glosa -h "$help" : "$@")"

# shellcheck disable=SC2034 # public: read by callers
GLOSA_VERSION="0.1.0"

# Explicit character sets: ranges like [A-Z] follow the locale's collation in
# Bash 3.2 and would match lowercase or accented letters.
_glosa_upper=ABCDEFGHIJKLMNOPQRSTUVWXYZ
_glosa_lower=abcdefghijklmnopqrstuvwxyz
_glosa_digit=0123456789

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

# Clears every table before a new parse.
_glosa_reset() {
    _glosa_err_code=0
    _glosa_err_msg=""
    _glosa_found=-1
    _glosa_name=""
    _glosa_o_short=()
    _glosa_o_long=()
    _glosa_o_argc=()
    _glosa_o_default=()
    _glosa_o_var=()
    _glosa_o_n=0
    _glosa_o_idx=" "
    _glosa_v_name=()
    _glosa_v_kind=()
    _glosa_v_elem=()
    _glosa_v_default=()
    _glosa_v_n=0
    _glosa_v_idx=" "
    _glosa_k_type=()
    _glosa_k_kids=()
    _glosa_k_ref=()
    _glosa_k_n=0
    _glosa_roots=()
    _glosa_opt_used=" "
    _glosa_has_shortcut=0
    _glosa_t_kind=()
    _glosa_t_ref=()
    _glosa_t_val=()
    _glosa_t_n=0
}

# ---------------------------------------------------------------------------
# Variables and options
# ---------------------------------------------------------------------------

# Derives the shell variable name for a usage element.
# "--skip-setup" -> skip_setup, "-t" -> _t, "<a-b>" -> a_b, FILE -> FILE.
# Sets _glosa_name; returns 2 when the result is not a valid name.
# usage: _glosa_derive_name <token>
_glosa_derive_name() {
    local _glosa_n="$1"
    case "$_glosa_n" in
        --*) _glosa_n="${_glosa_n#--}" ;;
        "<"*">") _glosa_n="${_glosa_n#<}"; _glosa_n="${_glosa_n%>}" ;;
    esac
    _glosa_n="${_glosa_n//-/_}"
    if [[ -z "$_glosa_n" || "$_glosa_n" == ["$_glosa_digit"]* || "$_glosa_n" == *[!"$_glosa_upper$_glosa_lower$_glosa_digit"_]* || "$_glosa_n" == _glosa_* ]]; then
        _glosa_fail 2 "invalid variable name '$_glosa_n'"
        return
    fi
    case "$_glosa_n" in
        _|IFS|PATH|HOME|PWD|OLDPWD|CDPATH|SHELLOPTS|BASHOPTS|BASH|BASH_*|BASHPID|\
        UID|EUID|PPID|GROUPS|RANDOM|SRANDOM|SECONDS|LINENO|OPTIND|OPTARG|OPTERR|\
        FUNCNAME|PIPESTATUS|DIRSTACK|EPOCHREALTIME|EPOCHSECONDS|LANG|LC_*|TMOUT|\
        PS1|PS2|PS3|PS4|PROMPT_COMMAND|GLOBIGNORE|POSIXLY_CORRECT|COMP_*)
            # Assigning these would break the shell or be silently lost.
            _glosa_fail 2 "reserved variable name '$_glosa_n'"
            return
            ;;
    esac
    _glosa_name="$_glosa_n"
}

# Finds the variable <name>. Sets _glosa_found to its index (-1: none).
# usage: _glosa_var_index <name>
_glosa_var_index() {
    case "$_glosa_v_idx" in
        *" $1="*)
            _glosa_found="${_glosa_v_idx#* "$1"=}"
            _glosa_found="${_glosa_found%% *}"
            ;;
        *) _glosa_found=-1 ;;
    esac
}

# Finds or creates the variable <name> for the usage element <identity>
# (e.g. "arg:<file>", "cmd:add", "opt:3"). Sets _glosa_found to its index;
# returns 2 when another element already uses that name.
# usage: _glosa_var <name> <kind> <identity>
_glosa_var() {
    case "$_glosa_v_idx" in
        *" $1="*)
            _glosa_found="${_glosa_v_idx#* "$1"=}"
            _glosa_found="${_glosa_found%% *}"
            ;;
        *) _glosa_found=-1 ;;
    esac
    if (( _glosa_found >= 0 )); then
        if [[ "${_glosa_v_elem[_glosa_found]}" != "$3" ]]; then
            _glosa_fail 2 "name collision: '$1'"
            return
        fi
        return 0
    fi
    _glosa_v_name[_glosa_v_n]="$1"
    _glosa_v_kind[_glosa_v_n]="$2"
    _glosa_v_elem[_glosa_v_n]="$3"
    _glosa_v_default[_glosa_v_n]=""
    _glosa_v_idx+="$1=$_glosa_v_n "
    _glosa_found=$_glosa_v_n
    _glosa_v_n=$((_glosa_v_n + 1))
}

# Registers an option, merging it with an existing one that shares its short
# or long form. Sets _glosa_found to the option index.
# usage: _glosa_add_option <short> <long> <argc> <default>
_glosa_add_option() {
    local _glosa_i=-1 _glosa_v
    case "$_glosa_o_idx" in
        *" ${1:-//}="*) _glosa_i="${_glosa_o_idx#* "$1"=}"; _glosa_i="${_glosa_i%% *}" ;;
        *" ${2:-//}="*) _glosa_i="${_glosa_o_idx#* "$2"=}"; _glosa_i="${_glosa_i%% *}" ;;
    esac
    if (( _glosa_i >= 0 )); then
        if [[ -z "${_glosa_o_short[_glosa_i]}" && -n "$1" ]]; then
            _glosa_o_short[_glosa_i]="$1"
            _glosa_o_idx+="$1=$_glosa_i "
        fi
        if [[ -z "${_glosa_o_long[_glosa_i]}" && -n "$2" ]]; then
            _glosa_o_long[_glosa_i]="$2"
            _glosa_o_idx+="$2=$_glosa_i "
        fi
        if (( $3 > _glosa_o_argc[_glosa_i] )); then
            _glosa_o_argc[_glosa_i]=$3
            _glosa_v_kind[_glosa_o_var[_glosa_i]]=value
        fi
        [[ -z "${_glosa_o_default[_glosa_i]}" ]] && _glosa_o_default[_glosa_i]="$4"
        _glosa_v_default[_glosa_o_var[_glosa_i]]="${_glosa_o_default[_glosa_i]}"
        _glosa_found=$_glosa_i
        return 0
    fi
    _glosa_derive_name "${2:-$1}" || return
    if (( $3 )); then
        _glosa_var "$_glosa_name" value "opt:$_glosa_o_n" || return
    else
        _glosa_var "$_glosa_name" flag "opt:$_glosa_o_n" || return
    fi
    _glosa_v=$_glosa_found
    _glosa_v_default[_glosa_v]="$4"
    _glosa_o_short[_glosa_o_n]="$1"
    _glosa_o_long[_glosa_o_n]="$2"
    _glosa_o_argc[_glosa_o_n]=$3
    _glosa_o_default[_glosa_o_n]="$4"
    _glosa_o_var[_glosa_o_n]=$_glosa_v
    [[ -n "$1" ]] && _glosa_o_idx+="$1=$_glosa_o_n "
    [[ -n "$2" ]] && _glosa_o_idx+="$2=$_glosa_o_n "
    _glosa_found=$_glosa_o_n
    _glosa_o_n=$((_glosa_o_n + 1))
}

# Parses _glosa_option_lines[] ("-o FILE --output=FILE  Description").
# usage: _glosa_parse_options
_glosa_parse_options() {
    local _glosa_line _glosa_forms _glosa_desc _glosa_tok _glosa_short _glosa_long _glosa_argc _glosa_def
    local _glosa_re='\[[Dd][Ee][Ff][Aa][Uu][Ll][Tt]: *([^]]*)\]' _glosa_rc=0 _glosa_glob=0 IFS=$' \t\n'
    case "$-" in *f*) _glosa_glob=1 ;; esac
    for _glosa_line in ${_glosa_option_lines[@]+"${_glosa_option_lines[@]}"}; do
        _glosa_forms="${_glosa_line%%  *}"
        _glosa_desc=""
        [[ "$_glosa_forms" != "$_glosa_line" ]] && _glosa_desc="${_glosa_line#*  }"
        _glosa_forms="${_glosa_forms//,/ }"
        _glosa_forms="${_glosa_forms//=/ }"
        _glosa_short=""
        _glosa_long=""
        _glosa_argc=0
        _glosa_def=""
        set -f
        # shellcheck disable=SC2086 # split the forms on spaces, globbing is off
        for _glosa_tok in $_glosa_forms; do
            case "$_glosa_tok" in
                --*) _glosa_long="$_glosa_tok" ;;
                -*) _glosa_short="$_glosa_tok" ;;
                *) _glosa_argc=1 ;;
            esac
        done
        (( _glosa_glob )) || set +f
        if (( _glosa_argc )) && [[ "$_glosa_desc" =~ $_glosa_re ]]; then
            _glosa_def="${BASH_REMATCH[1]}"
            _glosa_def="${_glosa_def%"${_glosa_def##*[! ]}"}"
        fi
        _glosa_add_option "$_glosa_short" "$_glosa_long" "$_glosa_argc" "$_glosa_def" || { _glosa_rc=$?; break; }
    done
    return "$_glosa_rc"
}

# Finds an option by one of its exact forms ("-x" or "--name"). Sets
# _glosa_found (-1: none).
# usage: _glosa_find_exact <form>
_glosa_find_exact() {
    case "$_glosa_o_idx" in
        *" $1="*)
            _glosa_found="${_glosa_o_idx#* "$1"=}"
            _glosa_found="${_glosa_found%% *}"
            ;;
        *) _glosa_found=-1 ;;
    esac
}

# Finds an option by its short form ("-x"). Sets _glosa_found (-1: none).
# usage: _glosa_find_short <-x>
_glosa_find_short() {
    _glosa_find_exact "$1"
}

# Finds an option by its long form or a unique prefix of it. Sets
# _glosa_found (-1: none); returns 1 when the prefix is ambiguous.
# usage: _glosa_find_long <--name>
_glosa_find_long() {
    local _glosa_i=0 _glosa_hits=0
    _glosa_find_exact "$1"
    (( _glosa_found >= 0 )) && return 0
    while (( _glosa_i < _glosa_o_n )); do
        if [[ -n "${_glosa_o_long[_glosa_i]}" && "${_glosa_o_long[_glosa_i]}" == "$1"* ]]; then
            _glosa_found=$_glosa_i
            _glosa_hits=$((_glosa_hits + 1))
        fi
        _glosa_i=$((_glosa_i + 1))
    done
    if (( _glosa_hits > 1 )); then
        _glosa_found=-1
        _glosa_fail 1 "Ambiguous option: '$1'"
        return
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Usage patterns
# ---------------------------------------------------------------------------

# Creates a pattern node. Sets _glosa_new to its id.
# usage: _glosa_node <type> <kids> <ref>
_glosa_node() {
    _glosa_k_type[_glosa_k_n]="$1"
    _glosa_k_kids[_glosa_k_n]="$2"
    _glosa_k_ref[_glosa_k_n]="$3"
    _glosa_new=$_glosa_k_n
    _glosa_k_n=$((_glosa_k_n + 1))
}

# Parses alternatives ("a b | c") up to a closing bracket or the end of the
# line. Sets _glosa_p_nodes to the resulting node ids.
_glosa_p_expr() {
    local -a _glosa_alts=()
    local _glosa_alt _glosa_ids=""
    while :; do
        _glosa_p_seq || return
        _glosa_alts[${#_glosa_alts[@]}]="$_glosa_p_nodes"
        [[ "${_glosa_tk[_glosa_tp]:-}" == "|" ]] || break
        _glosa_tp=$((_glosa_tp + 1))
    done
    if (( ${#_glosa_alts[@]} == 1 )); then
        _glosa_p_nodes="${_glosa_alts[0]}"
        return 0
    fi
    for _glosa_alt in "${_glosa_alts[@]}"; do
        if [[ "$_glosa_alt" == *" "* ]]; then
            _glosa_node seq "$_glosa_alt" ""
            _glosa_alt=$_glosa_new
        fi
        _glosa_ids+="${_glosa_ids:+ }$_glosa_alt"
    done
    _glosa_node either "$_glosa_ids" ""
    _glosa_p_nodes=$_glosa_new
}

# Parses a sequence of atoms. Sets _glosa_p_nodes.
_glosa_p_seq() {
    local _glosa_nodes="" _glosa_tok _glosa_last
    while (( _glosa_tp < _glosa_tn )); do
        _glosa_tok="${_glosa_tk[_glosa_tp]}"
        case "$_glosa_tok" in
            "|"|")"|"]") break ;;
            "...")
                if [[ -z "$_glosa_nodes" ]]; then
                    _glosa_fail 2 "unexpected '...'"
                    return
                fi
                _glosa_last="${_glosa_nodes##* }"
                _glosa_mark_repeated "$_glosa_last"
                _glosa_node oneormore "$_glosa_last" ""
                if [[ "$_glosa_nodes" == *" "* ]]; then
                    _glosa_nodes="${_glosa_nodes% *} $_glosa_new"
                else
                    _glosa_nodes=$_glosa_new
                fi
                _glosa_tp=$((_glosa_tp + 1))
                ;;
            *)
                _glosa_p_atom || return
                [[ -n "$_glosa_p_nodes" ]] && _glosa_nodes+="${_glosa_nodes:+ }$_glosa_p_nodes"
                ;;
        esac
    done
    _glosa_p_nodes="$_glosa_nodes"
}

# Parses one atom: a group, an option, an argument or a command. Sets
# _glosa_p_nodes (possibly several ids, for stacked short options).
_glosa_p_atom() {
    local _glosa_tok="${_glosa_tk[_glosa_tp]}" _glosa_inner _glosa_close _glosa_arg _glosa_nodes=""
    _glosa_tp=$((_glosa_tp + 1))
    case "$_glosa_tok" in
        "("|"[")
            if [[ "$_glosa_tok" == "[" && "${_glosa_tk[_glosa_tp]:-}" == options && "${_glosa_tk[_glosa_tp + 1]:-}" == "]" ]]; then
                _glosa_tp=$((_glosa_tp + 2))
                _glosa_has_shortcut=1
                _glosa_node shortcut "" ""
                _glosa_node optional "$_glosa_new" ""
                _glosa_p_nodes=$_glosa_new
                return 0
            fi
            _glosa_close=")"
            [[ "$_glosa_tok" == "[" ]] && _glosa_close="]"
            _glosa_p_expr || return
            _glosa_inner="$_glosa_p_nodes"
            if [[ "${_glosa_tk[_glosa_tp]:-}" != "$_glosa_close" ]]; then
                _glosa_fail 2 "unclosed group '$_glosa_tok'"
                return
            fi
            _glosa_tp=$((_glosa_tp + 1))
            if [[ "$_glosa_tok" == "[" ]]; then
                _glosa_node optional "$_glosa_inner" ""
                _glosa_p_nodes=$_glosa_new
            elif [[ "$_glosa_inner" == *" "* ]]; then
                _glosa_node seq "$_glosa_inner" ""
                _glosa_p_nodes=$_glosa_new
            else
                _glosa_p_nodes="$_glosa_inner"
            fi
            ;;
        --)
            _glosa_node dashes "" ""
            _glosa_p_nodes=$_glosa_new
            ;;
        --*)
            _glosa_arg=0
            if [[ "$_glosa_tok" == *=* ]]; then
                _glosa_arg=1
                _glosa_tok="${_glosa_tok%%=*}"
            fi
            # Exact names only: abbreviations are for the command line.
            _glosa_find_exact "$_glosa_tok"
            if (( _glosa_found < 0 )); then
                _glosa_add_option "" "$_glosa_tok" "$_glosa_arg" "" || return
            elif (( _glosa_arg )); then
                _glosa_add_option "" "$_glosa_tok" 1 "" || return
            fi
            _glosa_p_option_arg
            _glosa_opt_used+="$_glosa_found "
            _glosa_p_seen "${_glosa_o_var[_glosa_found]}"
            _glosa_node option "" "$_glosa_found"
            _glosa_p_nodes=$_glosa_new
            ;;
        -?*)
            _glosa_tok="${_glosa_tok#-}"
            while [[ -n "$_glosa_tok" ]]; do
                _glosa_find_short "-${_glosa_tok:0:1}"
                if (( _glosa_found < 0 )); then
                    _glosa_add_option "-${_glosa_tok:0:1}" "" 0 "" || return
                fi
                _glosa_tok="${_glosa_tok:1}"
                if (( _glosa_o_argc[_glosa_found] )); then
                    [[ -z "$_glosa_tok" ]] && _glosa_p_option_arg
                    _glosa_tok=""
                fi
                _glosa_opt_used+="$_glosa_found "
                _glosa_p_seen "${_glosa_o_var[_glosa_found]}"
                _glosa_node option "" "$_glosa_found"
                _glosa_nodes+="${_glosa_nodes:+ }$_glosa_new"
            done
            _glosa_p_nodes="$_glosa_nodes"
            ;;
        "<"*">"|["$_glosa_upper"]*)
            if [[ "$_glosa_tok" == ["$_glosa_upper"]* && "$_glosa_tok" == *[!"$_glosa_upper$_glosa_digit"_-]* ]]; then
                _glosa_p_command "$_glosa_tok"
                return
            fi
            _glosa_derive_name "$_glosa_tok" || return
            _glosa_var "$_glosa_name" value "arg:$_glosa_tok" || return
            _glosa_p_seen "$_glosa_found"
            _glosa_node argument "" "$_glosa_found"
            _glosa_p_nodes=$_glosa_new
            ;;
        ")"|"]")
            _glosa_fail 2 "unexpected '$_glosa_tok'"
            return
            ;;
        *)
            _glosa_p_command "$_glosa_tok"
            ;;
    esac
}

# Records that the current usage line names variable <v>, flagging lines
# that name the same variable twice.
# usage: _glosa_p_seen <v>
_glosa_p_seen() {
    if [[ "$_glosa_line_seen" == *" $1 "* ]]; then
        _glosa_line_dup=1
    else
        _glosa_line_seen+="$1 "
    fi
}

# Adds a command node for <word>. Sets _glosa_p_nodes.
_glosa_p_command() {
    _glosa_derive_name "$1" || return
    _glosa_var "$_glosa_name" flag "cmd:$1" || return
    _glosa_p_seen "$_glosa_found"
    _glosa_node command "" "$_glosa_found"
    _glosa_p_nodes=$_glosa_new
}

# Skips the argument placeholder that follows an option taking a value
# ("--output FILE" in a pattern). Keeps _glosa_found.
_glosa_p_option_arg() {
    local _glosa_next="${_glosa_tk[_glosa_tp]:-}"
    if (( _glosa_o_argc[_glosa_found] )) && [[ "$_glosa_next" == "<"*">" || ( "$_glosa_next" == ["$_glosa_upper"]* && "$_glosa_next" != *[!"$_glosa_upper$_glosa_digit"_-]* ) ]]; then
        _glosa_tp=$((_glosa_tp + 1))
    fi
}

# Marks every element under node <n> as repeatable: flags and commands
# become counters, values become lists.
# usage: _glosa_mark_repeated <n>
_glosa_mark_repeated() {
    local _glosa_kid _glosa_v
    case "${_glosa_k_type[$1]}" in
        argument|command) _glosa_v=${_glosa_k_ref[$1]} ;;
        option) _glosa_v=${_glosa_o_var[${_glosa_k_ref[$1]}]} ;;
        *)
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_mark_repeated "$_glosa_kid"
            done
            return 0
            ;;
    esac
    case "${_glosa_v_kind[_glosa_v]}" in
        flag) _glosa_v_kind[_glosa_v]=count ;;
        value) _glosa_v_kind[_glosa_v]=list ;;
    esac
}

# Counts how many times each variable can occur under node <n>; elements
# under "oneormore" count twice, alternatives take the maximum branch.
# usage: _glosa_count <n> <repeated: 0|1>
_glosa_count() {
    local _glosa_t="${_glosa_k_type[$1]}" _glosa_kid _glosa_rep="$2" _glosa_v _glosa_i
    local -a _glosa_before _glosa_best
    case "$_glosa_t" in
        argument|command)
            _glosa_v=${_glosa_k_ref[$1]}
            _glosa_cnt[_glosa_v]=$(( _glosa_cnt[_glosa_v] + 1 + _glosa_rep ))
            ;;
        option)
            _glosa_v=${_glosa_o_var[${_glosa_k_ref[$1]}]}
            _glosa_cnt[_glosa_v]=$(( _glosa_cnt[_glosa_v] + 1 + _glosa_rep ))
            ;;
        either)
            _glosa_before=("${_glosa_cnt[@]}")
            _glosa_best=("${_glosa_cnt[@]}")
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_cnt=("${_glosa_before[@]}")
                _glosa_count "$_glosa_kid" "$_glosa_rep"
                _glosa_i=0
                while (( _glosa_i < _glosa_v_n )); do
                    (( _glosa_cnt[_glosa_i] > _glosa_best[_glosa_i] )) && _glosa_best[_glosa_i]=${_glosa_cnt[_glosa_i]}
                    _glosa_i=$((_glosa_i + 1))
                done
            done
            _glosa_cnt=("${_glosa_best[@]}")
            ;;
        oneormore)
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_count "$_glosa_kid" 1
            done
            ;;
        *)
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_count "$_glosa_kid" "$_glosa_rep"
            done
            ;;
    esac
}

# Parses _glosa_usage_lines[] into one "seq" root per line, then marks
# repeatable variables as count (flags, commands) or list (values).
# usage: _glosa_parse_patterns
_glosa_parse_patterns() {
    local _glosa_line _glosa_i _glosa_root _glosa_oldifs="$IFS" _glosa_glob=0 _glosa_bar="|"
    case "$-" in *f*) _glosa_glob=1 ;; esac
    local _glosa_zeros=""
    local -a _glosa_root_vars=()
    _glosa_counted=""
    for _glosa_line in "${_glosa_usage_lines[@]}"; do
        _glosa_line_seen=" "
        _glosa_line_dup=0
        _glosa_line="${_glosa_line//(/ ( }"
        _glosa_line="${_glosa_line//)/ ) }"
        _glosa_line="${_glosa_line//[/ [ }"
        _glosa_line="${_glosa_line//]/ ] }"
        _glosa_line="${_glosa_line//"$_glosa_bar"/ $_glosa_bar }"
        _glosa_line="${_glosa_line//.../ ... }"
        set -f
        IFS=' '
        # shellcheck disable=SC2206 # split on spaces on purpose, globbing is off
        _glosa_tk=($_glosa_line)
        IFS="$_glosa_oldifs"
        (( _glosa_glob )) || set +f
        _glosa_tn=${#_glosa_tk[@]}
        _glosa_tp=1
        _glosa_p_expr || return
        if (( _glosa_tp < _glosa_tn )); then
            _glosa_fail 2 "unexpected '${_glosa_tk[_glosa_tp]}'"
            return
        fi
        _glosa_node seq "$_glosa_p_nodes" ""
        _glosa_roots[${#_glosa_roots[@]}]=$_glosa_new
        # "..." already marked its elements; only lines that name an element
        # twice need the full count (alternatives take the maximum branch).
        if (( _glosa_line_dup )); then
            _glosa_counted+=" $_glosa_new"
            _glosa_root_vars[_glosa_new]="$_glosa_line_seen"
        fi
    done
    [[ -z "$_glosa_counted" ]] && return 0
    _glosa_i=0
    while (( _glosa_i < _glosa_v_n )); do
        _glosa_zeros+="0 "
        _glosa_i=$((_glosa_i + 1))
    done
    for _glosa_root in $_glosa_counted; do
        # shellcheck disable=SC2206 # a list of zeros
        _glosa_cnt=($_glosa_zeros)
        _glosa_count "$_glosa_root" 0
        for _glosa_i in ${_glosa_root_vars[_glosa_root]}; do
            if (( _glosa_cnt[_glosa_i] > 1 )); then
                case "${_glosa_v_kind[_glosa_i]}" in
                    flag) _glosa_v_kind[_glosa_i]=count ;;
                    value) _glosa_v_kind[_glosa_i]=list ;;
                esac
            fi
        done
    done
    return 0
}

# Renders node <n> as an s-expression into _glosa_dump (for tests).
# usage: _glosa_tree_dump <n>
_glosa_tree_dump() {
    local _glosa_t="${_glosa_k_type[$1]}" _glosa_out _glosa_kid
    case "$_glosa_t" in
        argument|command) _glosa_out="($_glosa_t ${_glosa_v_name[${_glosa_k_ref[$1]}]})" ;;
        option) _glosa_out="(option ${_glosa_v_name[${_glosa_o_var[${_glosa_k_ref[$1]}]}]})" ;;
        *)
            _glosa_out="($_glosa_t"
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_tree_dump "$_glosa_kid"
                _glosa_out+=" $_glosa_dump"
            done
            _glosa_out+=")"
            ;;
    esac
    _glosa_dump="$_glosa_out"
}

# ---------------------------------------------------------------------------
# Command-line arguments
# ---------------------------------------------------------------------------

# Splits the arguments into option and positional tokens. Returns 1 with a
# usage error message for unknown or malformed options.
# usage: _glosa_tokenize [args...]
_glosa_tokenize() {
    # A single "for" pass with no function calls per argument: in Bash 3.2,
    # "shift" and every call made from a frame with thousands of positional
    # parameters cost O(n), which would make the loop quadratic.
    local _glosa_a _glosa_name _glosa_val _glosa_chars _glosa_dd=0
    local _glosa_need=-1 _glosa_need_name=""
    _glosa_t_kind=()
    _glosa_t_ref=()
    _glosa_t_val=()
    _glosa_t_n=0
    for _glosa_a in "$@"; do
        if (( _glosa_need >= 0 )); then
            # The value of the previous option.
            _glosa_t_kind[_glosa_t_n]=opt
            _glosa_t_ref[_glosa_t_n]="$_glosa_need"
            _glosa_t_val[_glosa_t_n]="$_glosa_a"
            _glosa_t_n=$((_glosa_t_n + 1))
            _glosa_need=-1
            continue
        fi
        if (( _glosa_dd )); then
            _glosa_t_kind[_glosa_t_n]=pos
            _glosa_t_ref[_glosa_t_n]=""
            _glosa_t_val[_glosa_t_n]="$_glosa_a"
            _glosa_t_n=$((_glosa_t_n + 1))
            continue
        fi
        case "$_glosa_a" in
            --)
                _glosa_dd=1
                ;;
            --*)
                _glosa_name="${_glosa_a%%=*}"
                _glosa_find_long "$_glosa_name" || return
                if (( _glosa_found < 0 )); then
                    _glosa_fail 1 "Unknown option: '$_glosa_name'"
                    return
                fi
                _glosa_name="${_glosa_o_long[_glosa_found]}"
                if [[ "$_glosa_a" == *=* ]]; then
                    if (( ! _glosa_o_argc[_glosa_found] )); then
                        _glosa_fail 1 "Option '$_glosa_name' does not take an argument"
                        return
                    fi
                    _glosa_t_kind[_glosa_t_n]=opt
                    _glosa_t_ref[_glosa_t_n]="$_glosa_found"
                    _glosa_t_val[_glosa_t_n]="${_glosa_a#*=}"
                    _glosa_t_n=$((_glosa_t_n + 1))
                elif (( _glosa_o_argc[_glosa_found] )); then
                    _glosa_need=$_glosa_found
                    _glosa_need_name="$_glosa_name"
                else
                    _glosa_t_kind[_glosa_t_n]=opt
                    _glosa_t_ref[_glosa_t_n]="$_glosa_found"
                    _glosa_t_val[_glosa_t_n]=""
                    _glosa_t_n=$((_glosa_t_n + 1))
                fi
                ;;
            -?*)
                _glosa_chars="${_glosa_a#-}"
                while [[ -n "$_glosa_chars" ]]; do
                    _glosa_name="-${_glosa_chars:0:1}"
                    _glosa_chars="${_glosa_chars:1}"
                    _glosa_find_short "$_glosa_name"
                    if (( _glosa_found < 0 )); then
                        _glosa_fail 1 "Unknown option: '$_glosa_name'"
                        return
                    fi
                    _glosa_val=""
                    if (( _glosa_o_argc[_glosa_found] )); then
                        if [[ -z "$_glosa_chars" ]]; then
                            _glosa_need=$_glosa_found
                            _glosa_need_name="$_glosa_name"
                            break
                        fi
                        _glosa_val="$_glosa_chars"
                        _glosa_chars=""
                    fi
                    _glosa_t_kind[_glosa_t_n]=opt
                    _glosa_t_ref[_glosa_t_n]="$_glosa_found"
                    _glosa_t_val[_glosa_t_n]="$_glosa_val"
                    _glosa_t_n=$((_glosa_t_n + 1))
                done
                ;;
            *)
                _glosa_t_kind[_glosa_t_n]=pos
                _glosa_t_ref[_glosa_t_n]=""
                _glosa_t_val[_glosa_t_n]="$_glosa_a"
                _glosa_t_n=$((_glosa_t_n + 1))
                ;;
        esac
    done
    if (( _glosa_need >= 0 )); then
        _glosa_fail 1 "Option '$_glosa_need_name' requires an argument"
        return
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

# Matches node <n> against the unconsumed tokens in _glosa_left (" i j k ")
# and records "var:token" pairs in _glosa_coll. On failure both are restored.
# Semantics follow docopt: optional and oneormore are greedy, either keeps the
# branch that leaves the fewest tokens.
# usage: _glosa_m <n>
_glosa_m() {
    local _glosa_kid _glosa_k _glosa_v _glosa_sl _glosa_sc
    local _glosa_bl _glosa_bc _glosa_min=-1 _glosa_len=-1 _glosa_times=0 _glosa_keep _glosa_got
    # Leaves never change state when they fail; only groups save it.
    case "${_glosa_k_type[$1]}" in
        seq|either)
            _glosa_sl="$_glosa_left"
            _glosa_sc="$_glosa_coll"
            ;;
    esac
    case "${_glosa_k_type[$1]}" in
        argument|command)
            _glosa_v=${_glosa_k_ref[$1]}
            # Fast path: the first unconsumed token is usually a positional.
            _glosa_k="${_glosa_left# }"
            _glosa_k="${_glosa_k%% *}"
            if [[ -n "$_glosa_k" && "${_glosa_t_kind[_glosa_k]}" == pos ]]; then
                if [[ "${_glosa_k_type[$1]}" == command && "${_glosa_t_val[_glosa_k]}" != "${_glosa_v_elem[_glosa_v]#cmd:}" ]]; then
                    return 1
                fi
                _glosa_left="${_glosa_left#" $_glosa_k"}"
                _glosa_coll+=" $_glosa_v:$_glosa_k"
                return 0
            fi
            for _glosa_k in $_glosa_left; do
                [[ "${_glosa_t_kind[_glosa_k]}" == pos ]] || continue
                if [[ "${_glosa_k_type[$1]}" == command && "${_glosa_t_val[_glosa_k]}" != "${_glosa_v_elem[_glosa_v]#cmd:}" ]]; then
                    return 1
                fi
                _glosa_left="${_glosa_left/ $_glosa_k / }"
                _glosa_coll+=" $_glosa_v:$_glosa_k"
                return 0
            done
            return 1
            ;;
        option)
            for _glosa_k in $_glosa_left; do
                if [[ "${_glosa_t_kind[_glosa_k]}" == opt && "${_glosa_t_ref[_glosa_k]}" == "${_glosa_k_ref[$1]}" ]]; then
                    _glosa_left="${_glosa_left/ $_glosa_k / }"
                    _glosa_coll+=" ${_glosa_o_var[${_glosa_k_ref[$1]}]}:$_glosa_k"
                    return 0
                fi
            done
            return 1
            ;;
        seq)
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                if ! _glosa_m "$_glosa_kid"; then
                    _glosa_left="$_glosa_sl"
                    _glosa_coll="$_glosa_sc"
                    return 1
                fi
            done
            return 0
            ;;
        optional)
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_m "$_glosa_kid" || :
            done
            return 0
            ;;
        either)
            for _glosa_kid in ${_glosa_k_kids[$1]}; do
                _glosa_left="$_glosa_sl"
                _glosa_coll="$_glosa_sc"
                if _glosa_m "$_glosa_kid"; then
                    _glosa_len=${#_glosa_left}
                    if (( _glosa_min < 0 || _glosa_len < _glosa_min )); then
                        _glosa_min=$_glosa_len
                        _glosa_bl="$_glosa_left"
                        _glosa_bc="$_glosa_coll"
                    fi
                fi
            done
            if (( _glosa_min < 0 )); then
                _glosa_left="$_glosa_sl"
                _glosa_coll="$_glosa_sc"
                return 1
            fi
            _glosa_left="$_glosa_bl"
            _glosa_coll="$_glosa_bc"
            return 0
            ;;
        oneormore)
            _glosa_kid="${_glosa_k_kids[$1]}"
            if [[ "${_glosa_k_type[_glosa_kid]}" == argument ]]; then
                # "<x>..." in one pass: take every positional in order and
                # keep the options, as repeated matching would.
                _glosa_v=${_glosa_k_ref[_glosa_kid]}
                _glosa_keep=" "
                _glosa_got=""
                for _glosa_k in $_glosa_left; do
                    if [[ "${_glosa_t_kind[_glosa_k]}" == pos ]]; then
                        _glosa_got+=" $_glosa_v:$_glosa_k"
                    else
                        _glosa_keep+="$_glosa_k "
                    fi
                done
                [[ -n "$_glosa_got" ]] || return 1
                _glosa_left="$_glosa_keep"
                _glosa_coll+="$_glosa_got"
                return 0
            fi
            while _glosa_m "$_glosa_kid"; do
                _glosa_times=$((_glosa_times + 1))
                (( ${#_glosa_left} == _glosa_len )) && break
                _glosa_len=${#_glosa_left}
            done
            (( _glosa_times > 0 ))
            return
            ;;
        shortcut)
            for _glosa_k in $_glosa_left; do
                [[ "${_glosa_t_kind[_glosa_k]}" == opt ]] || continue
                case " $_glosa_shortcut_opts " in
                    *" ${_glosa_t_ref[_glosa_k]} "*)
                        _glosa_left="${_glosa_left/ $_glosa_k / }"
                        _glosa_coll+=" ${_glosa_o_var[${_glosa_t_ref[_glosa_k]}]}:$_glosa_k"
                        ;;
                esac
            done
            return 0
            ;;
        dashes)
            return 0
            ;;
    esac
    return 1
}

# Tries each usage line in order; the first one that consumes every token
# wins. Fills _glosa_r_val[v]: true/false for flags, a number for counters,
# a token index for values ("" when absent) and token indices for lists.
# usage: _glosa_match
_glosa_match() {
    local _glosa_root _glosa_all="" _glosa_k=0 _glosa_pair _glosa_v _glosa_n
    while (( _glosa_k < _glosa_t_n )); do
        _glosa_all+=" $_glosa_k"
        _glosa_k=$((_glosa_k + 1))
    done
    _glosa_all+=" "
    # Options the [options] shortcut may consume: those no pattern names.
    _glosa_shortcut_opts=" "
    if (( _glosa_has_shortcut )); then
        _glosa_k=0
        while (( _glosa_k < _glosa_o_n )); do
            [[ "$_glosa_opt_used" == *" $_glosa_k "* ]] || _glosa_shortcut_opts+="$_glosa_k "
            _glosa_k=$((_glosa_k + 1))
        done
    fi
    for _glosa_root in "${_glosa_roots[@]}"; do
        _glosa_left="$_glosa_all"
        _glosa_coll=""
        _glosa_m "$_glosa_root" || continue
        [[ "$_glosa_left" == *[!\ ]* ]] && continue
        _glosa_r_val=()
        _glosa_v=0
        while (( _glosa_v < _glosa_v_n )); do
            case "${_glosa_v_kind[_glosa_v]}" in
                flag) _glosa_r_val[_glosa_v]=false ;;
                count) _glosa_r_val[_glosa_v]=0 ;;
                *) _glosa_r_val[_glosa_v]="" ;;
            esac
            _glosa_v=$((_glosa_v + 1))
        done
        for _glosa_pair in $_glosa_coll; do
            _glosa_v=${_glosa_pair%%:*}
            _glosa_k=${_glosa_pair#*:}
            case "${_glosa_v_kind[_glosa_v]}" in
                flag) _glosa_r_val[_glosa_v]=true ;;
                count) _glosa_n=${_glosa_r_val[_glosa_v]}; _glosa_r_val[_glosa_v]=$((_glosa_n + 1)) ;;
                value) _glosa_r_val[_glosa_v]=$_glosa_k ;;
                list) _glosa_r_val[_glosa_v]+="${_glosa_r_val[_glosa_v]:+ }$_glosa_k" ;;
            esac
        done
        return 0
    done
    _glosa_fail 1 "Invalid arguments."
}

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

# Records an error and returns its code (1: usage error, 2: invalid help).
# usage: _glosa_fail <code> <message>
_glosa_fail() {
    _glosa_err_code="$1"
    _glosa_err_msg="$2"
    return "$1"
}

# ---------------------------------------------------------------------------
# Help sections
# ---------------------------------------------------------------------------

# Splits the help text into the usage patterns and the option lines.
# Sets _glosa_usage_block, _glosa_usage_lines[] and _glosa_option_lines[].
# usage: _glosa_sections <help>
_glosa_sections() {
    local _glosa_rest="$1"$'\n' _glosa_line _glosa_trim _glosa_state=none _glosa_prog=""
    _glosa_usage_block=""
    _glosa_usage_lines=()
    _glosa_option_lines=()
    while [[ -n "$_glosa_rest" ]]; do
        _glosa_line="${_glosa_rest%%$'\n'*}"
        _glosa_rest="${_glosa_rest#*$'\n'}"
        _glosa_line="${_glosa_line%$'\r'}"
        # Sections continue while lines are indented (docopt rule).
        if [[ "$_glosa_state" != none ]]; then
            case "$_glosa_line" in
                " "*|$'\t'*)
                    _glosa_trim="${_glosa_line//$'\t'/  }"
                    _glosa_trim="${_glosa_trim#"${_glosa_trim%%[! ]*}"}"
                    if [[ -z "$_glosa_trim" ]]; then
                        # A whitespace-only line is a blank line.
                        _glosa_state=none
                        continue
                    fi
                    if [[ "$_glosa_state" == usage ]]; then
                        _glosa_usage_block+=$'\n'"$_glosa_line"
                        _glosa_trim="${_glosa_trim%"${_glosa_trim##*[! ]}"}"
                        if [[ -z "$_glosa_prog" ]]; then
                            _glosa_prog="${_glosa_trim%% *}"
                            _glosa_usage_lines[0]="$_glosa_trim"
                        elif [[ "${_glosa_trim%% *}" == "$_glosa_prog" ]]; then
                            _glosa_usage_lines[${#_glosa_usage_lines[@]}]="$_glosa_trim"
                        else
                            # A line that does not start with the program
                            # name wraps the previous one (docopt rule).
                            _glosa_usage_lines[${#_glosa_usage_lines[@]} - 1]+=" $_glosa_trim"
                        fi
                    else
                        _glosa_trim="${_glosa_trim%"${_glosa_trim##*[! ]}"}"
                        if [[ "$_glosa_trim" == -* ]]; then
                            _glosa_option_lines[${#_glosa_option_lines[@]}]="$_glosa_trim"
                        elif (( ${#_glosa_option_lines[@]} )); then
                            # A wrapped description (it may hold the default).
                            _glosa_option_lines[${#_glosa_option_lines[@]} - 1]+="  $_glosa_trim"
                        fi
                    fi
                    continue
                    ;;
            esac
            _glosa_state=none
        fi
        # Only lines with a colon can be section headers.
        [[ "$_glosa_line" == *:* ]] || continue
        _glosa_trim="${_glosa_line//$'\t'/  }"
        _glosa_trim="${_glosa_trim#"${_glosa_trim%%[! ]*}"}"
        _glosa_trim="${_glosa_trim%"${_glosa_trim##*[! ]}"}"
        if [[ -z "$_glosa_usage_block" && "$_glosa_trim" == [Uu][Ss][Aa][Gg][Ee]:* ]]; then
            _glosa_state=usage
            _glosa_usage_block="$_glosa_line"
            _glosa_trim="${_glosa_trim:6}"
            _glosa_trim="${_glosa_trim#"${_glosa_trim%%[! ]*}"}"
            if [[ -n "$_glosa_trim" ]]; then
                _glosa_prog="${_glosa_trim%% *}"
                _glosa_usage_lines[0]="$_glosa_trim"
            fi
        elif [[ "$_glosa_trim" == *[Oo][Pp][Tt][Ii][Oo][Nn][Ss]:* ]]; then
            _glosa_state=options
            # The first option may share the header line (docopt rule).
            _glosa_trim="${_glosa_trim#*:}"
            _glosa_trim="${_glosa_trim#"${_glosa_trim%%[! ]*}"}"
            [[ "$_glosa_trim" == -* ]] && _glosa_option_lines[${#_glosa_option_lines[@]}]="$_glosa_trim"
        fi
    done
    if [[ -z "$_glosa_usage_block" ]]; then
        _glosa_fail 2 "no usage section found"
        return
    fi
    if (( ${#_glosa_usage_lines[@]} == 0 )); then
        _glosa_fail 2 "empty usage section"
        return
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Running a parse
# ---------------------------------------------------------------------------

# Runs every phase. Sets _glosa_status to ok, help, version, 1 (usage error)
# or 2 (invalid help text).
# usage: _glosa_run <version> <help> [args...]
_glosa_run() {
    local _glosa_ver="$1" _glosa_text="$2"
    shift 2
    _glosa_reset
    if ! { _glosa_sections "$_glosa_text" && _glosa_parse_options && _glosa_parse_patterns; }; then
        _glosa_status=2
        return
    fi
    if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
        _glosa_status=help
    elif [[ -n "$_glosa_ver" && "${1-}" == "--version" ]]; then
        _glosa_status=version
    elif _glosa_tokenize "$@" && _glosa_match; then
        _glosa_status=ok
    else
        _glosa_status=1
    fi
}

# Computes the final value of variable <v>: _glosa_value for scalars,
# _glosa_items[] for lists.
# usage: _glosa_value_of <v>
_glosa_value_of() {
    local _glosa_k _glosa_def _glosa_oldifs="$IFS"
    _glosa_value="${_glosa_r_val[$1]}"
    _glosa_items=()
    case "${_glosa_v_kind[$1]}" in
        value)
            if [[ -n "$_glosa_value" ]]; then
                _glosa_value="${_glosa_t_val[_glosa_value]}"
            else
                _glosa_value="${_glosa_v_default[$1]}"
            fi
            ;;
        list)
            for _glosa_k in $_glosa_value; do
                _glosa_items[${#_glosa_items[@]}]="${_glosa_t_val[_glosa_k]}"
            done
            _glosa_def="${_glosa_v_default[$1]}"
            if (( ${#_glosa_items[@]} == 0 )) && [[ -n "$_glosa_def" ]]; then
                IFS=' '
                # shellcheck disable=SC2206 # split the default on spaces, globbing is off
                _glosa_items=($_glosa_def)
                IFS="$_glosa_oldifs"
            fi
            ;;
    esac
}

# Quotes <value> for eval inside single quotes into _glosa_q. Unlike
# printf %q, the result is identical in every Bash version: Bash 3.2's %q
# leaves "~" unescaped, so the eval would expand it.
# usage: _glosa_quote <value>
_glosa_quote() {
    local _glosa_sq="'" _glosa_esc="'\''"
    # Unquoted on purpose: Bash 3.2 keeps the inner quotes of the replacement
    # when the whole expansion is double-quoted. Assignments do not split.
    _glosa_q=${1//"$_glosa_sq"/"$_glosa_esc"}
    _glosa_q="'$_glosa_q'"
}

# Builds "name='value'" shell code for variable <v> into _glosa_code. Lists
# become "name=()" followed by one "name[i]='item'" line per item: Bash 3.2
# corrupts \001 bytes inside an eval'd compound assignment.
# usage: _glosa_code_for <v>
_glosa_code_for() {
    local _glosa_item _glosa_i=0
    _glosa_value_of "$1"
    if [[ "${_glosa_v_kind[$1]}" == list ]]; then
        _glosa_code="${_glosa_v_name[$1]}=()"
        for _glosa_item in ${_glosa_items[@]+"${_glosa_items[@]}"}; do
            _glosa_quote "$_glosa_item"
            _glosa_code+=$'\n'"${_glosa_v_name[$1]}[$_glosa_i]=$_glosa_q"
            _glosa_i=$((_glosa_i + 1))
        done
    else
        _glosa_quote "$_glosa_value"
        _glosa_code="${_glosa_v_name[$1]}=$_glosa_q"
    fi
}

# Saves the caller's shell options and switches to the ones glosa needs.
_glosa_shell_enter() {
    _glosa_saved_opts="$-"
    _glosa_saved_nocase=0
    shopt -q nocasematch && _glosa_saved_nocase=1
    set +eu
    set -f
    shopt -u nocasematch
}

# Restores the options saved by _glosa_shell_enter.
_glosa_shell_leave() {
    [[ "$_glosa_saved_opts" == *f* ]] || set +f
    [[ "$_glosa_saved_opts" == *u* ]] && set -u
    [[ "$_glosa_saved_opts" == *e* ]] && set -e
    (( _glosa_saved_nocase )) && shopt -s nocasematch
    return 0
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Parses "$@" against the usage described in <help> and assigns one global
# variable per declared element. Prints the help and exits 0 when the first
# argument is -h or --help (or --version, when a version is given); prints
# a usage error and exits 1 when the arguments do not match; exits 2 when
# the help text itself is invalid.
# usage: glosa::parse [--version <version>] <help> [args...]
glosa::parse() {
    _glosa_parse_body "$@"
    # Printing and exiting happen here, after the body's locals (LC_ALL, IFS)
    # are gone, so the caller's EXIT trap sees the caller's own state.
    case "$_glosa_status" in
        ok) return 0 ;;
        help|version) printf '%s\n' "$_glosa_out"; exit 0 ;;
        1) printf '%s\n\n%s\n' "$_glosa_err_msg" "$_glosa_usage_block" >&2; exit 1 ;;
        *) printf 'glosa: invalid help text: %s\n' "$_glosa_err_msg" >&2; exit 2 ;;
    esac
}

# Does the work of glosa::parse: runs every phase and, on success, assigns
# the variables. Sets _glosa_status, and _glosa_out to the text to print.
_glosa_parse_body() {
    # The C locale makes string operations much faster in Bash 3.2; "local"
    # restores the caller's locale on return.
    local LC_ALL=C IFS=$' \t\n' _glosa_version="" _glosa_help _glosa_v=0
    if [[ "${1-}" == "--version" && $# -ge 2 ]]; then
        _glosa_version="$2"
        shift 2
    fi
    _glosa_help="${1-}"
    (( $# )) && shift
    _glosa_shell_enter
    _glosa_run "$_glosa_version" "$_glosa_help" "$@"
    _glosa_out="$_glosa_help"
    [[ "$_glosa_status" == version ]] && _glosa_out="$_glosa_version"
    if [[ "$_glosa_status" == ok ]]; then
        while (( _glosa_v < _glosa_v_n )); do
            case "${_glosa_v_kind[_glosa_v]}" in
                flag|count)
                    printf -v "${_glosa_v_name[_glosa_v]}" '%s' "${_glosa_r_val[_glosa_v]}"
                    ;;
                value)
                    _glosa_value_of "$_glosa_v"
                    printf -v "${_glosa_v_name[_glosa_v]}" '%s' "$_glosa_value"
                    ;;
                *)
                    # Values never enter the eval text: only the validated
                    # name and the expansion of _glosa_items do.
                    _glosa_value_of "$_glosa_v"
                    eval "${_glosa_v_name[_glosa_v]}=(\${_glosa_items[@]+\"\${_glosa_items[@]}\"})"
                    ;;
            esac
            _glosa_v=$((_glosa_v + 1))
        done
    fi
    _glosa_shell_leave
}

# Command-line entry point: prints shell code for eval, ending in "exit N"
# for help, version and errors.
# usage: glosa [--version <version>] -h <help> : [args...]
glosa::main() {
    local LC_ALL=C IFS=$' \t\n' _glosa_version="" _glosa_help _glosa_v=0
    if [[ "${1-}" == "--version" && $# -ge 2 ]]; then
        _glosa_version="$2"
        shift 2
    fi
    if [[ "${1-}" != "-h" || $# -lt 3 || "$3" != ":" ]]; then
        printf 'usage: glosa [--version <version>] -h <help> : [args...]\n' >&2
        return 2
    fi
    _glosa_help="$2"
    shift 3
    _glosa_shell_enter
    _glosa_run "$_glosa_version" "$_glosa_help" "$@"
    case "$_glosa_status" in
        ok)
            while (( _glosa_v < _glosa_v_n )); do
                _glosa_code_for "$_glosa_v"
                printf '%s\n' "$_glosa_code"
                _glosa_v=$((_glosa_v + 1))
            done
            return 0
            ;;
        help|version)
            [[ "$_glosa_status" == version ]] && _glosa_help="$_glosa_version"
            _glosa_quote "$_glosa_help"
            printf "printf '%%s\\\\n' %s\nexit 0\n" "$_glosa_q"
            return 0
            ;;
        1)
            printf '%s\n\n%s\n' "$_glosa_err_msg" "$_glosa_usage_block" >&2
            printf 'exit 1\n'
            return 1
            ;;
        *)
            printf 'glosa: invalid help text: %s\n' "$_glosa_err_msg" >&2
            printf 'exit 2\n'
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    glosa::main "$@"
    exit $?
fi
