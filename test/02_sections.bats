#!/usr/bin/env bats
# shellcheck shell=bats
# shellcheck disable=SC2154 # _glosa_* globals are set by the sourced library

load test_helper

setup() {
    # shellcheck source=glosa.sh
    source "$GLOSA"
}

@test "inline usage line" {
    _glosa_sections 'Usage: prog [-v] <a>'
    [ "${#_glosa_usage_lines[@]}" -eq 1 ]
    [ "${_glosa_usage_lines[0]}" = "prog [-v] <a>" ]
}

@test "multi-line usage stops at blank line and ignores Examples" {
    _glosa_sections 'Prints a greeting

Usage:
  greet <name>

Examples:
  greet world'
    [ "${#_glosa_usage_lines[@]}" -eq 1 ]
    [ "${_glosa_usage_lines[0]}" = "greet <name>" ]
}

@test "a usage line that does not start with the program name continues the previous one" {
    _glosa_sections 'Usage:
  prog [--foo] [--bar]
       [--baz] <file>
  prog list'
    [ "${#_glosa_usage_lines[@]}" -eq 2 ]
    [ "${_glosa_usage_lines[0]}" = "prog [--foo] [--bar] [--baz] <file>" ]
    [ "${_glosa_usage_lines[1]}" = "prog list" ]
}

@test "the inline usage line sets the program name for the next lines" {
    _glosa_sections 'Usage: prog add <x>
         [--force]
       prog rm <x>'
    [ "${#_glosa_usage_lines[@]}" -eq 2 ]
    [ "${_glosa_usage_lines[0]}" = "prog add <x> [--force]" ]
}

@test "case-insensitive header" {
    _glosa_sections 'USAGE:
  prog <x>'
    [ "${_glosa_usage_lines[0]}" = "prog <x>" ]
}

@test "options section collects only dash lines" {
    _glosa_sections 'Resize a picture

Usage:
  resize <file>
  resize <file> --small

Options:
  -h --help   Show this screen.
  -s --small  Make it small'
    [ "${#_glosa_usage_lines[@]}" -eq 2 ]
    [ "${#_glosa_option_lines[@]}" -eq 2 ]
    [ "${_glosa_option_lines[0]}" = "-h --help   Show this screen." ]
    [ "${_glosa_option_lines[1]}" = "-s --small  Make it small" ]
}

@test "any section ending in options: counts" {
    _glosa_sections 'Usage: prog [options]

Global options:
  -q  Quiet
    continuation line
  -v  Verbose'
    [ "${#_glosa_option_lines[@]}" -eq 2 ]
    [ "${_glosa_option_lines[1]}" = "-v  Verbose" ]
}

@test "options can start on the header line" {
    _glosa_sections 'Usage: prog [options]

Options: -v  Verbose
  -q  Quiet'
    [ "${#_glosa_option_lines[@]}" -eq 2 ]
    [ "${_glosa_option_lines[0]}" = "-v  Verbose" ]
    [ "${_glosa_option_lines[1]}" = "-q  Quiet" ]
}

@test "text after the options header is not an option" {
    _glosa_sections 'Usage: prog [options]

Options: all of them are optional
  -q  Quiet'
    [ "${#_glosa_option_lines[@]}" -eq 1 ]
    [ "${_glosa_option_lines[0]}" = "-q  Quiet" ]
}

@test "prose after the options header is not an option" {
    _glosa_sections 'Usage: prog [options]

Common options: -v, -q.'
    [ "${#_glosa_option_lines[@]}" -eq 0 ]
}

@test "usage block is printed verbatim" {
    _glosa_sections 'Usage:
   run
   run <context>

Other text'
    [ "$_glosa_usage_block" = 'Usage:
   run
   run <context>' ]
}

@test "CRLF and tabs parse like LF and spaces" {
    _glosa_sections $'Usage:\r\n\tprog <a>\r\n\r\nOptions:\r\n\t-q\tQuiet\r\n'
    [ "${_glosa_usage_lines[0]}" = "prog <a>" ]
    [ "${#_glosa_option_lines[@]}" -eq 1 ]
    [ "$_glosa_usage_block" = $'Usage:\n\tprog <a>' ]
}

@test "missing usage is a developer error" {
    run _glosa_sections 'No usage here'
    [ "$status" -eq 2 ]
    _glosa_sections 'No usage here' || true
    [ "$_glosa_err_msg" = "no usage section found" ]
}

@test "empty usage is a developer error" {
    _glosa_sections 'Usage:

Options:' || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "empty usage section" ]
}
