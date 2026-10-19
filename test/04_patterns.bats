#!/usr/bin/env bats
# shellcheck shell=bats
# shellcheck disable=SC2154 # _glosa_* globals are set by the sourced library

load test_helper

setup() {
    # shellcheck source=glosa.sh
    source "$GLOSA"
}

FEAT_OPTIONS='
Options:
  -o FILE --output=FILE  Output file [default: out.txt]
  -q --quiet             Quiet
  -t                     T flag
  -w --watch             Watch
  -v                     Verbosity
  --port=<p>             Port [default: 8080]'

# Parses a whole help text.
parse() {
    _glosa_reset
    _glosa_sections "$1" && _glosa_parse_options && _glosa_parse_patterns
}

# Prints the s-expression of root $1.
root() {
    _glosa_tree_dump "${_glosa_roots[$1]}"
    echo "$_glosa_dump"
}

# Prints the kind of variable $1.
kind() {
    _glosa_var_index "$1"
    echo "${_glosa_v_kind[$_glosa_found]}"
}

@test "alternative usage lines with a flag" {
    parse 'Usage:
  resize <file>
  resize <file> --small

Options:
  -s --small  Make it small'
    [ "${#_glosa_roots[@]}" -eq 2 ]
    [ "$(root 0)" = "(seq (argument file))" ]
    [ "$(root 1)" = "(seq (argument file) (option small))" ]
}

@test "dispatcher with variadic and help alternatives" {
    parse 'Usage:
   run
   run <context>
   run <context> <command> [<args>...]
   run -h | --help'
    [ "$(root 0)" = "(seq)" ]
    [ "$(root 2)" = "(seq (argument context) (argument command) (optional (oneormore (argument args))))" ]
    [ "$(root 3)" = "(seq (either (option _h) (option help)))" ]
    [ "$(kind args)" = "list" ]
    [ "$(kind context)" = "value" ]
    [ "$(kind help)" = "flag" ]
}

@test "optional positional and optional flag" {
    parse 'Usage:
  projects [<filter>] [--pick]'
    [ "$(root 0)" = "(seq (optional (argument filter)) (optional (option pick)))" ]
}

@test "subcommands" {
    parse 'Usage:
  store list_items
  store purge [<optional_path_file>]'
    [ "$(root 1)" = "(seq (command purge) (optional (argument optional_path_file)))" ]
    [ "$(kind purge)" = "flag" ]
}

@test "options shortcut" {
    parse "Usage:
  prog [options] <file>
$FEAT_OPTIONS"
    [ "$(root 0)" = "(seq (optional (shortcut)) (argument file))" ]
}

@test "stacked shorts, double dash and variadic" {
    parse "Usage:
  prog [-tw] -- <rest>...
$FEAT_OPTIONS"
    [ "$(root 0)" = "(seq (optional (option _t) (option watch)) (dashes) (oneormore (argument rest)))" ]
    [ "$(kind rest)" = "list" ]
}

@test "required group with alternatives" {
    parse 'Usage:
  prog (add | rm) <name>...'
    [ "$(root 0)" = "(seq (either (command add) (command rm)) (oneormore (argument name)))" ]
}

@test "multi-word alternatives become sequences" {
    parse 'Usage:
  prog (go <where> | stop)'
    [ "$(root 0)" = "(seq (either (seq (command go) (argument where)) (command stop)))" ]
}

@test "repeated flag is a counter" {
    parse "Usage:
  prog serve [-v...]
$FEAT_OPTIONS"
    [ "$(kind _v)" = "count" ]
}

@test "command repeated in one line is a counter" {
    parse 'Usage:
  prog x x'
    [ "$(kind x)" = "count" ]
}

@test "alternatives do not make an element repeated" {
    parse 'Usage:
  prog (x | x)'
    [ "$(kind x)" = "flag" ]
}

@test "repeatable option with argument is a list" {
    parse 'Usage:
  prog [--file=<f>...]'
    [ "$(kind file)" = "list" ]
    [ "$(root 0)" = "(seq (optional (oneormore (option file))))" ]
}

@test "uppercase positional keeps its name" {
    parse 'Usage:
  prog FILE [--out=PATH]'
    [ "$(root 0)" = "(seq (argument FILE) (optional (option out)))" ]
    [ "$(kind out)" = "value" ]
}

@test "option argument given as a separate pattern token" {
    parse "Usage:
  prog --output FILE <x>
$FEAT_OPTIONS"
    [ "$(root 0)" = "(seq (option output) (argument x))" ]
}

@test "trailing words are commands" {
    parse 'Usage:
  follow <filename>  Extra words'
    [ "$(root 0)" = "(seq (argument filename) (command Extra) (command words))" ]
}

@test "unclosed bracket is a developer error" {
    parse 'Usage: prog [<a>' || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "unclosed group '['" ]
}

@test "unclosed parenthesis is a developer error" {
    parse 'Usage: prog (<a>' || true
    [ "$_glosa_err_msg" = "unclosed group '('" ]
}

@test "unexpected closing parenthesis is a developer error" {
    parse 'Usage: prog <a>)' || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "unexpected ')'" ]
}

@test "same name for different elements is a developer error" {
    parse 'Usage: prog <file> --file' || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "name collision: 'file'" ]
}

@test "the same element in several lines is not a collision" {
    parse 'Usage:
  prog <file>
  prog <file> --force'
    [ "$(kind file)" = "value" ]
}

@test "reserved names are rejected in patterns" {
    parse 'Usage: prog <_glosa_x>' || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "invalid variable name '_glosa_x'" ]
}

@test "repeat counting still applies on later lines" {
    parse 'Usage:
  prog <a>
  prog go <b> <b>'
    [ "$(kind a)" = "value" ]
    [ "$(kind b)" = "list" ]
}

@test "long options in patterns are looked up by their exact name" {
    parse 'Usage: prog --fo

Options:
  --foo  Foo
  --fob  Fob'
    [ "$(root 0)" = "(seq (option fo))" ]
    [ "$(kind fo)" = "flag" ]
}

@test "a non-ASCII short option in a pattern is reported whole" {
    local LC_ALL=C
    parse 'Usage: prog -é' || true
    [ "$_glosa_err_code" -eq 2 ]
    [ "$_glosa_err_msg" = "invalid variable name '_é'" ]
}
