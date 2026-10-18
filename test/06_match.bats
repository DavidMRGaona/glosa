#!/usr/bin/env bats
# shellcheck shell=bats
# shellcheck disable=SC2154 # _glosa_* globals are set by the sourced library

load test_helper

setup() {
    # shellcheck source=glosa.sh
    source "$GLOSA"
}

STORE='Usage:
  store list_items
  store purge [<optional_path_file>]'

DISPATCHER='Usage:
   run
   run <context>
   run <context> <command> [<args>...]
   run -h | --help'

FEAT='Usage:
  prog [options] <file>
  prog serve [--port=<p>] [-v...]
  prog (add | rm) <name>...
  prog [-tw] -- <rest>...

Options:
  -o FILE --output=FILE  Output file [default: out.txt]
  -q --quiet             Quiet
  -t                     T flag
  -w --watch             Watch
  -v                     Verbosity
  --port=<p>             Port [default: 8080]'

# Parses <help> and matches the remaining arguments.
match() {
    local help="$1"
    shift
    _glosa_reset
    _glosa_sections "$help" && _glosa_parse_options && _glosa_parse_patterns &&
        _glosa_tokenize "$@" && _glosa_match
}

# Prints the matched value of variable $1: flags and counters as is, values
# as the token text, lists as token texts joined by ",".
val() {
    local v k out=""
    _glosa_var_index "$1"
    v=$_glosa_found
    case "${_glosa_v_kind[v]}" in
        flag | count) echo "${_glosa_r_val[v]}" ;;
        value)
            if [[ -n "${_glosa_r_val[v]}" ]]; then echo "${_glosa_t_val[${_glosa_r_val[v]}]}"; else echo ""; fi
            ;;
        list)
            for k in ${_glosa_r_val[v]}; do out+="${out:+,}${_glosa_t_val[k]}"; done
            echo "$out"
            ;;
    esac
}

@test "subcommand selects its line" {
    match "$STORE" list_items
    [ "$(val list_items)" = true ]
    [ "$(val purge)" = false ]
}

@test "subcommand with optional positional" {
    match "$STORE" purge /x
    [ "$(val purge)" = true ]
    [ "$(val optional_path_file)" = /x ]
}

@test "unknown subcommand fails" {
    run match "$STORE" nope
    [ "$status" -eq 1 ]
    match "$STORE" nope || true
    [ "$_glosa_err_msg" = "Invalid arguments." ]
}

@test "missing required arguments fail" {
    run match "$STORE"
    [ "$status" -eq 1 ]
}

@test "extra argument fails" {
    run match "$STORE" list_items extra
    [ "$status" -eq 1 ]
}

@test "variadic collects the rest" {
    match "$DISPATCHER" ctx cmd a 'b c'
    [ "$(val context)" = ctx ]
    [ "$(val command)" = cmd ]
    [ "$(val args)" = "a,b c" ]
}

@test "no arguments match the empty line" {
    match "$DISPATCHER"
    [ "$(val context)" = "" ]
    [ "$(val args)" = "" ]
    [ "$(val help)" = false ]
}

@test "options may come before positionals" {
    match 'Usage:
  resize <file>
  resize <file> --small

Options:
  -s --small  Make it small' --small pic.jpg
    [ "$(val small)" = true ]
    [ "$(val file)" = pic.jpg ]
}

@test "trailing words are required commands" {
    run match 'Usage:
  follow <filename>  Extra words' f.json
    [ "$status" -eq 1 ]
    match 'Usage:
  follow <filename>  Extra words' f.json Extra words
    [ "$(val Extra)" = true ]
}

@test "options named in any pattern are not part of the shortcut" {
    match "$FEAT" serve --port 9
    [ "$(val serve)" = true ]
    [ "$(val file)" = "" ]
    [ "$(val port)" = 9 ]
}

@test "first matching line wins" {
    match 'Usage:
  prog <a>
  prog x' x
    [ "$(val a)" = x ]
    [ "$(val x)" = false ]
}

@test "required alternative with variadic" {
    match "$FEAT" add a b c
    [ "$(val add)" = true ]
    [ "$(val rm)" = false ]
    [ "$(val name)" = "a,b,c" ]
}

@test "repeated short flag counts" {
    match "$FEAT" serve -vvv
    [ "$(val serve)" = true ]
    [ "$(val _v)" = 3 ]
}

@test "options shortcut accepts declared options" {
    match "$FEAT" -q a.txt
    [ "$(val quiet)" = true ]
    [ "$(val file)" = a.txt ]
}

@test "double dash in the pattern" {
    match "$FEAT" -tw -- a -b
    [ "$(val _t)" = true ]
    [ "$(val watch)" = true ]
    [ "$(val rest)" = "a,-b" ]
}

@test "mutually exclusive flags" {
    run match 'Usage:
  prog [--file=<f>...] [-v | -q] [<x>]' -v -q
    [ "$status" -eq 1 ]
}

@test "repeated option collects values" {
    match 'Usage:
  prog [--file=<f>...] [-v | -q] [<x>]' --file=a --file=b
    [ "$(val file)" = "a,b" ]
}

@test "repeated command counts" {
    match 'Usage:
  prog FILE [--out=PATH]
  prog x x' x x
    [ "$(val x)" = 2 ]
    [ "$(val FILE)" = "" ]
}

@test "500 variadic arguments in order and under a second" {
    # Timed in a plain shell: bats' DEBUG trap slows every function call.
    # shellcheck disable=SC2016 # the script is expanded by the inner shell
    run "$GLOSA_TEST_BASH" -c '
        source "$1"
        many=(); i=0
        while (( i < 500 )); do many[i]="arg$i"; i=$((i + 1)); done
        start=$SECONDS
        _glosa_reset
        _glosa_sections "$2" && _glosa_parse_options && _glosa_parse_patterns &&
            _glosa_tokenize ctx cmd "${many[@]}" && _glosa_match || exit 9
        elapsed=$((SECONDS - start))
        _glosa_var_index args
        set -- ${_glosa_r_val[$_glosa_found]}
        echo "$elapsed $# ${_glosa_t_val[$1]} ${_glosa_t_val[${500}]}"
    ' _ "$GLOSA" "$DISPATCHER"
    [ "$status" -eq 0 ]
    read -r elapsed count first last <<< "$output"
    (( elapsed <= 1 ))
    [ "$count" -eq 500 ]
    [ "$first" = arg0 ]
    [ "$last" = arg499 ]
}

@test "thousands of variadic arguments stay fast" {
    # shellcheck disable=SC2016 # the script is expanded by the inner shell
    run "$GLOSA_TEST_BASH" -c '
        source "$1"
        many=(); i=0
        while (( i < 5000 )); do many[i]="x$i"; i=$((i + 1)); done
        start=$SECONDS
        glosa::parse "Usage: p [-v] <args>..." "${many[@]}"
        echo "$((SECONDS - start)) ${#args[@]} ${args[4999]}"
    ' _ "$GLOSA"
    [ "$status" -eq 0 ]
    read -r elapsed count last <<< "$output"
    (( elapsed <= 2 ))
    [ "$count" -eq 5000 ]
    [ "$last" = x4999 ]
}
