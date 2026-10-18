#!/usr/bin/env bats
# shellcheck shell=bats
# shellcheck disable=SC2154 # _glosa_* globals are set by the sourced library

load test_helper

setup() {
    # shellcheck source=glosa.sh
    source "$GLOSA"
    _glosa_reset
}

# Parses the given option lines and prints "short|long|argc|default|var|kind"
# for option $1 (an index).
parse_lines() {
    _glosa_option_lines=("$@")
    _glosa_parse_options
}

describe() {
    local i="$1" v="${_glosa_o_var[$1]}"
    echo "${_glosa_o_short[$i]}|${_glosa_o_long[$i]}|${_glosa_o_argc[$i]}|${_glosa_o_default[$i]}|${_glosa_v_name[$v]}|${_glosa_v_kind[$v]}"
}

@test "short and long alias form one flag" {
    parse_lines "-h --help  Show this screen."
    [ "$_glosa_o_n" -eq 1 ]
    [ "$(describe 0)" = "-h|--help|0||help|flag" ]
}

@test "option with argument and default" {
    parse_lines "-o FILE --output=FILE  Output file [default: out.txt]"
    [ "$(describe 0)" = "-o|--output|1|out.txt|output|value" ]
}

@test "default marker is case-insensitive" {
    parse_lines "--port=<p>  Port [Default: 8080]"
    [ "$(describe 0)" = "|--port|1|8080|port|value" ]
}

@test "comma separated forms with angle argument" {
    parse_lines "-o <f>, --out <f>  x"
    [ "$(describe 0)" = "-o|--out|1||out|value" ]
}

@test "short-only option is named with a leading underscore" {
    parse_lines "-t  T flag"
    [ "$(describe 0)" = "-t||0||_t|flag" ]
}

@test "dashes become underscores" {
    parse_lines "--verbose-mode  V"
    [ "$(describe 0)" = "|--verbose-mode|0||verbose_mode|flag" ]
}

@test "description mentioning another option is not parsed as a form" {
    parse_lines "-q  quiet, unlike -x"
    [ "$_glosa_o_n" -eq 1 ]
    [ "$(describe 0)" = "-q||0||_q|flag" ]
}

@test "long option abbreviation resolves a unique prefix" {
    parse_lines "--verbose-mode  V" "--port=<p>  P" "--portal  P"
    _glosa_find_long --verb
    [ "$_glosa_found" -eq 0 ]
    _glosa_find_long --port
    [ "$_glosa_found" -eq 1 ]
    _glosa_find_long --nope
    [ "$_glosa_found" -eq -1 ]
}

@test "ambiguous abbreviation is a usage error" {
    parse_lines "--verbose  V" "--version  V"
    run _glosa_find_long --ver
    [ "$status" -eq 1 ]
    _glosa_find_long --ver || true
    [ "$_glosa_err_msg" = "Ambiguous option: '--ver'" ]
}

@test "short lookup" {
    parse_lines "-a  A" "-b --bee  B"
    _glosa_find_short -b
    [ "$_glosa_found" -eq 1 ]
    _glosa_find_short -c
    [ "$_glosa_found" -eq -1 ]
}

@test "invalid variable name is a developer error" {
    run parse_lines "--2fa  x"
    [ "$status" -eq 2 ]
    parse_lines "--2fa  x" || true
    [ "$_glosa_err_msg" = "invalid variable name '2fa'" ]
}

@test "names reserved for glosa internals are rejected" {
    _glosa_derive_name "<_glosa_x>" || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "invalid variable name '_glosa_x'" ]
}

@test "derived names" {
    _glosa_derive_name "<a-b>"; [ "$_glosa_name" = "a_b" ]
    _glosa_derive_name "FILE"; [ "$_glosa_name" = "FILE" ]
    _glosa_derive_name "list_items"; [ "$_glosa_name" = "list_items" ]
    _glosa_derive_name "-t"; [ "$_glosa_name" = "_t" ]
    _glosa_derive_name "--skip-setup"; [ "$_glosa_name" = "skip_setup" ]
}
