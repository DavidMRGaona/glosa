#!/usr/bin/env bats
# shellcheck shell=bats
# shellcheck disable=SC2154 # _glosa_* globals are set by the sourced library

load test_helper

setup() {
    # shellcheck source=glosa.sh
    source "$GLOSA"
    _glosa_reset
    _glosa_option_lines=(
        "-o FILE --output=FILE  Output file [default: out.txt]"
        "-q --quiet  Quiet"
        "--verbose-mode  Verbose"
        "-t  T flag"
        "-w --watch  Watch"
    )
    _glosa_parse_options
}

# Prints one line per token: "pos|<value>" or "opt|<var name>|<value>".
tokens() {
    local k=0
    while (( k < _glosa_t_n )); do
        if [[ "${_glosa_t_kind[k]}" == pos ]]; then
            echo "pos|${_glosa_t_val[k]}"
        else
            echo "opt|${_glosa_v_name[${_glosa_o_var[${_glosa_t_ref[k]}]}]}|${_glosa_t_val[k]}"
        fi
        k=$((k + 1))
    done
}

@test "long option with = value" {
    _glosa_tokenize --output=y
    [ "$(tokens)" = "opt|output|y" ]
}

@test "long option with separate value" {
    _glosa_tokenize --output y
    [ "$(tokens)" = "opt|output|y" ]
}

@test "short option with attached value" {
    _glosa_tokenize -ox
    [ "$(tokens)" = "opt|output|x" ]
}

@test "short option with separate value" {
    _glosa_tokenize -o x
    [ "$(tokens)" = "opt|output|x" ]
}

@test "stacked short flags" {
    _glosa_tokenize -tw
    [ "$(tokens)" = "opt|_t|
opt|watch|" ]
}

@test "stacked flags ending in an option that takes the rest" {
    _glosa_tokenize -tox
    [ "$(tokens)" = "opt|_t|
opt|output|x" ]
}

@test "double dash makes everything positional" {
    _glosa_tokenize -- a -b
    [ "$(tokens)" = "pos|a
pos|-b" ]
}

@test "single dash and empty string are positionals" {
    _glosa_tokenize - ""
    [ "$_glosa_t_n" -eq 2 ]
    [ "$(tokens)" = "pos|-
pos|" ]
}

@test "long option abbreviation" {
    _glosa_tokenize --verb
    [ "$(tokens)" = "opt|verbose_mode|" ]
}

@test "unknown long option" {
    run _glosa_tokenize --nope
    [ "$status" -eq 1 ]
    _glosa_tokenize --nope || true
    [ "$_glosa_err_msg" = "Unknown option: '--nope'" ]
}

@test "unknown short option" {
    _glosa_tokenize -x || true
    [ "$_glosa_err_code" -eq 1 ]
    [ "$_glosa_err_msg" = "Unknown option: '-x'" ]
}

@test "a non-ASCII short option is reported whole" {
    # glosa runs in the C locale, where "é" is two bytes.
    local LC_ALL=C
    _glosa_tokenize -é || true
    [ "$_glosa_err_msg" = "Unknown option: '-é'" ]
    _glosa_tokenize -qé || true
    [ "$_glosa_err_msg" = "Unknown option: '-é'" ]
}

@test "missing value" {
    _glosa_tokenize --output || true
    [ "$_glosa_err_code" -eq 1 ]
    [ "$_glosa_err_msg" = "Option '--output' requires an argument" ]
    _glosa_tokenize a -o || true
    [ "$_glosa_err_msg" = "Option '-o' requires an argument" ]
}

@test "value given to a flag" {
    _glosa_tokenize --quiet=1 || true
    [ "$_glosa_err_code" -eq 1 ]
    [ "$_glosa_err_msg" = "Option '--quiet' does not take an argument" ]
}

@test "glob characters and spaces stay literal" {
    _glosa_tokenize '*' 'a b'
    [ "$(tokens)" = "pos|*
pos|a b" ]
}
