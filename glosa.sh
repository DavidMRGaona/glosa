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
    _glosa_v_name=()
    _glosa_v_kind=()
    _glosa_v_default=()
    _glosa_v_n=0
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
    if [[ -z "$_glosa_n" || "$_glosa_n" == [0-9]* || "$_glosa_n" == *[!A-Za-z0-9_]* || "$_glosa_n" == _glosa_* ]]; then
        _glosa_fail 2 "invalid variable name '$_glosa_n'"
        return
    fi
    _glosa_name="$_glosa_n"
}

# Finds or creates the variable <name>. Sets _glosa_found to its index.
# usage: _glosa_var <name> <kind>
_glosa_var() {
    local _glosa_i=0
    while (( _glosa_i < _glosa_v_n )); do
        if [[ "${_glosa_v_name[_glosa_i]}" == "$1" ]]; then
            _glosa_found=$_glosa_i
            return 0
        fi
        _glosa_i=$((_glosa_i + 1))
    done
    _glosa_v_name[_glosa_v_n]="$1"
    _glosa_v_kind[_glosa_v_n]="$2"
    _glosa_v_default[_glosa_v_n]=""
    _glosa_found=$_glosa_v_n
    _glosa_v_n=$((_glosa_v_n + 1))
}

# Registers an option, merging it with an existing one that shares its short
# or long form. Sets _glosa_found to the option index.
# usage: _glosa_add_option <short> <long> <argc> <default>
_glosa_add_option() {
    local _glosa_i=0 _glosa_v
    while (( _glosa_i < _glosa_o_n )); do
        if [[ ( -n "$1" && "${_glosa_o_short[_glosa_i]}" == "$1" ) || ( -n "$2" && "${_glosa_o_long[_glosa_i]}" == "$2" ) ]]; then
            [[ -z "${_glosa_o_short[_glosa_i]}" ]] && _glosa_o_short[_glosa_i]="$1"
            [[ -z "${_glosa_o_long[_glosa_i]}" ]] && _glosa_o_long[_glosa_i]="$2"
            if (( $3 > _glosa_o_argc[_glosa_i] )); then
                _glosa_o_argc[_glosa_i]=$3
                _glosa_v_kind[_glosa_o_var[_glosa_i]]=value
            fi
            [[ -z "${_glosa_o_default[_glosa_i]}" ]] && _glosa_o_default[_glosa_i]="$4"
            _glosa_v_default[_glosa_o_var[_glosa_i]]="${_glosa_o_default[_glosa_i]}"
            _glosa_found=$_glosa_i
            return 0
        fi
        _glosa_i=$((_glosa_i + 1))
    done
    _glosa_derive_name "${2:-$1}" || return
    if (( $3 )); then
        _glosa_var "$_glosa_name" value
    else
        _glosa_var "$_glosa_name" flag
    fi
    _glosa_v=$_glosa_found
    _glosa_v_default[_glosa_v]="$4"
    _glosa_o_short[_glosa_o_n]="$1"
    _glosa_o_long[_glosa_o_n]="$2"
    _glosa_o_argc[_glosa_o_n]=$3
    _glosa_o_default[_glosa_o_n]="$4"
    _glosa_o_var[_glosa_o_n]=$_glosa_v
    _glosa_found=$_glosa_o_n
    _glosa_o_n=$((_glosa_o_n + 1))
}

# Parses _glosa_option_lines[] ("-o FILE --output=FILE  Description").
# usage: _glosa_parse_options
_glosa_parse_options() {
    local _glosa_line _glosa_forms _glosa_desc _glosa_tok _glosa_short _glosa_long _glosa_argc _glosa_def
    local _glosa_re='\[default: *([^]]*)\]' _glosa_nocase=0 _glosa_rc=0
    shopt -q nocasematch && _glosa_nocase=1
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
        while [[ -n "$_glosa_forms" ]]; do
            _glosa_forms="${_glosa_forms#"${_glosa_forms%%[! ]*}"}"
            [[ -z "$_glosa_forms" ]] && break
            _glosa_tok="${_glosa_forms%% *}"
            _glosa_forms="${_glosa_forms#"$_glosa_tok"}"
            case "$_glosa_tok" in
                --*) _glosa_long="$_glosa_tok" ;;
                -*) _glosa_short="$_glosa_tok" ;;
                *) _glosa_argc=1 ;;
            esac
        done
        if (( _glosa_argc )); then
            shopt -s nocasematch
            [[ "$_glosa_desc" =~ $_glosa_re ]] && _glosa_def="${BASH_REMATCH[1]}"
            (( _glosa_nocase )) || shopt -u nocasematch
            _glosa_def="${_glosa_def%"${_glosa_def##*[! ]}"}"
        fi
        _glosa_add_option "$_glosa_short" "$_glosa_long" "$_glosa_argc" "$_glosa_def" || { _glosa_rc=$?; break; }
    done
    return "$_glosa_rc"
}

# Finds an option by its short form ("-x"). Sets _glosa_found (-1: none).
# usage: _glosa_find_short <-x>
_glosa_find_short() {
    local _glosa_i=0
    _glosa_found=-1
    while (( _glosa_i < _glosa_o_n )); do
        if [[ "${_glosa_o_short[_glosa_i]}" == "$1" ]]; then
            _glosa_found=$_glosa_i
            return 0
        fi
        _glosa_i=$((_glosa_i + 1))
    done
}

# Finds an option by its long form or a unique prefix of it. Sets
# _glosa_found (-1: none); returns 1 when the prefix is ambiguous.
# usage: _glosa_find_long <--name>
_glosa_find_long() {
    local _glosa_i=0 _glosa_hits=0
    _glosa_found=-1
    while (( _glosa_i < _glosa_o_n )); do
        if [[ "${_glosa_o_long[_glosa_i]}" == "$1" ]]; then
            _glosa_found=$_glosa_i
            return 0
        fi
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
    local _glosa_rest="$1" _glosa_line _glosa_trim _glosa_state=none _glosa_nocase=0
    _glosa_usage_block=""
    _glosa_usage_lines=()
    _glosa_option_lines=()
    shopt -q nocasematch && _glosa_nocase=1
    shopt -s nocasematch
    while [[ -n "$_glosa_rest" ]]; do
        _glosa_line="${_glosa_rest%%$'\n'*}"
        if [[ "$_glosa_line" == "$_glosa_rest" ]]; then
            _glosa_rest=""
        else
            _glosa_rest="${_glosa_rest#*$'\n'}"
        fi
        _glosa_line="${_glosa_line%$'\r'}"
        _glosa_trim="${_glosa_line//$'\t'/  }"
        _glosa_trim="${_glosa_trim#"${_glosa_trim%%[! ]*}"}"
        _glosa_trim="${_glosa_trim%"${_glosa_trim##*[! ]}"}"
        # Sections continue while lines are indented (docopt rule).
        if [[ "$_glosa_state" != none && ( "$_glosa_line" == " "* || "$_glosa_line" == $'\t'* ) ]]; then
            if [[ "$_glosa_state" == usage ]]; then
                _glosa_usage_block+=$'\n'"$_glosa_line"
                [[ -n "$_glosa_trim" ]] && _glosa_usage_lines[${#_glosa_usage_lines[@]}]="$_glosa_trim"
            elif [[ "$_glosa_trim" == -* ]]; then
                _glosa_option_lines[${#_glosa_option_lines[@]}]="$_glosa_trim"
            fi
            continue
        fi
        _glosa_state=none
        if [[ -z "$_glosa_usage_block" && "$_glosa_trim" == usage:* ]]; then
            _glosa_state=usage
            _glosa_usage_block="$_glosa_line"
            _glosa_trim="${_glosa_trim:6}"
            _glosa_trim="${_glosa_trim#"${_glosa_trim%%[! ]*}"}"
            [[ -n "$_glosa_trim" ]] && _glosa_usage_lines[${#_glosa_usage_lines[@]}]="$_glosa_trim"
        elif [[ "$_glosa_trim" == *options: ]]; then
            _glosa_state=options
        fi
    done
    (( _glosa_nocase )) || shopt -u nocasematch
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

# Parses "$@" against the usage described in <help> and assigns one global
# variable per declared element.
# usage: glosa::parse [--version <version>] <help> [args...]
glosa::parse() {
    printf 'glosa: not implemented\n' >&2
    return 2
}

# Command-line entry point: prints shell code for eval.
# usage: glosa [--version <version>] -h <help> : [args...]
glosa::main() {
    printf 'usage: glosa [--version <version>] -h <help> : [args...]\n' >&2
    return 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    glosa::main "$@"
    exit $?
fi
