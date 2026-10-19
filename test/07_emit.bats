#!/usr/bin/env bats
# shellcheck shell=bats
# shellcheck disable=SC2030,SC2031,SC2034 # GLOSA_DUMP is set per test, read by glosa_case
# shellcheck disable=SC2016 # inner shells expand their own scripts

load test_helper

RESIZE='Resize a picture

Usage:
  resize <file>
  resize <file> --small

Options:
  -h --help   Show this screen.
  -s --small  Make it small'

SAY='Say a text

Usage:
  say <text>
  say <text> --enter

Options:
  -e --enter  Press enter afterwards'

DISPATCHER='Usage:
   run
   run <context>
   run <context> <command> [<args>...]
   run -h | --help'

STORE='Usage:
  store list_items
  store purge [<optional_path_file>]'

PROJECTS='List known projects

Usage:
  projects [<filter>] [--pick]'

FEAT='Usage:
  prog [options] <file>
  prog serve [--port=<p>] [-v...]
  prog (add | rm) <name>...

Options:
  -o FILE --output=FILE  Output file [default: out.txt]
  -q --quiet             Quiet
  -v                     Verbosity
  --port=<p>             Port [default: 8080]'

@test "every declared variable is defined under set -u" {
    GLOSA_DUMP="file small help"
    glosa_both "$RESIZE" pic.jpg
    [ "$output" = "exit=0
file=pic.jpg
small=false
help=false" ]
}

# shellcheck disable=SC2088 # literal tildes on purpose
@test "values round-trip without injection" {
    local pwned="$BATS_TEST_TMPDIR/pwned" v expected
    local -a values=(
        "it's"
        'a"b'
        "\$(touch '$pwned')"
        "\`touch '$pwned'\`"
        "x'; touch '$pwned'; '"
        'a;b'
        $'l1\nl2'
        '\back\slash'
        '*'
        ' leading and trailing '
        '~'
        '~/x'
        'a:~'
        'a=~'
        $'ctl\001\177'
    )
    for v in "${values[@]}"; do
        GLOSA_DUMP="text"
        glosa_both "$SAY" "$v"
        expected="exit=0
text=$(glosa_esc "$v")"
        [ "$output" = "$expected" ]
        GLOSA_DUMP="args"
        glosa_both "$DISPATCHER" c s "$v" "$v"
        expected="exit=0
args[]=2
args[0]=$(glosa_esc "$v")
args[1]=$(glosa_esc "$v")"
        [ "$output" = "$expected" ]
    done
    [ ! -e "$pwned" ]
}

@test "-h as first argument prints the full help and exits 0" {
    GLOSA_DUMP=""
    glosa_both "$PROJECTS" -h
    [ "$output" = "exit=0" ]
    [ "$(< "$BATS_TEST_TMPDIR/out.cli")" = "$PROJECTS" ]
    [ "$(< "$BATS_TEST_TMPDIR/out.src")" = "$PROJECTS" ]
}

@test "--help with more arguments still prints the help" {
    GLOSA_DUMP=""
    glosa_both "$PROJECTS" --help x
    [ "$output" = "exit=0" ]
    [ "$(< "$BATS_TEST_TMPDIR/out.src")" = "$PROJECTS" ]
}

@test "-h after other arguments is a usage error" {
    GLOSA_DUMP=""
    glosa_both "$RESIZE" pic.jpg -h
    [ "$output" = "exit=1" ]
}

@test "a usage error names a non-ASCII option whole in both modes" {
    GLOSA_DUMP=""
    glosa_both "$RESIZE" pic.jpg -é
    [ "$output" = "exit=1" ]
    [ "$(head -1 "$BATS_TEST_TMPDIR/err.cli")" = "Unknown option: '-é'" ]
    [ "$(head -1 "$BATS_TEST_TMPDIR/err.src")" = "Unknown option: '-é'" ]
}

@test "help text with shell syntax is printed literally" {
    local help='Usage: prog <x>

Costs $HOME and `id` and $(id) and \n'
    GLOSA_DUMP=""
    glosa_both "$help" -h
    [ "$(< "$BATS_TEST_TMPDIR/out.cli")" = "$help" ]
    [ "$(< "$BATS_TEST_TMPDIR/out.src")" = "$help" ]
}

@test "--version prints the configured version" {
    run "$GLOSA_TEST_BASH" -c 'source "$1"; glosa::parse --version 1.2.3 "Usage: prog [<x>]" --version' _ "$GLOSA"
    [ "$status" -eq 0 ]
    [ "$output" = "1.2.3" ]
    run "$GLOSA_TEST_BASH" -c 'eval "$("$BASH" "$1" --version 1.2.3 -h "Usage: prog [<x>]" : --version)"' _ "$GLOSA"
    [ "$status" -eq 0 ]
    [ "$output" = "1.2.3" ]
}

@test "--version without a configured version is an unknown option" {
    GLOSA_DUMP=""
    glosa_both "Usage: prog [<x>]" --version
    [ "$output" = "exit=1" ]
    [[ "$(< "$BATS_TEST_TMPDIR/err.src")" == "Unknown option: '--version'"* ]]
}

@test "usage error prints the message and the usage block" {
    GLOSA_DUMP=""
    glosa_both "$STORE" nope
    [ "$output" = "exit=1" ]
    local expected='Invalid arguments.

Usage:
  store list_items
  store purge [<optional_path_file>]'
    [ "$(< "$BATS_TEST_TMPDIR/err.src")" = "$expected" ]
    [ "$(< "$BATS_TEST_TMPDIR/err.cli")" = "$expected" ]
}

@test "CLI prints exit code for usage errors" {
    run "$GLOSA_TEST_BASH" "$GLOSA" -h "$STORE" : nope
    [ "$status" -eq 1 ]
    [ "${lines[${#lines[@]}-1]}" = "exit 1" ]
}

@test "invalid help is exit 2 in both modes" {
    GLOSA_DUMP=""
    glosa_both 'Usage: prog [<a>' x
    [ "$output" = "exit=2" ]
    [ "$(< "$BATS_TEST_TMPDIR/err.src")" = "glosa: invalid help text: unclosed group '['" ]
    run "$GLOSA_TEST_BASH" "$GLOSA" -h 'Usage: prog [<a>' : x
    [ "$status" -eq 2 ]
    [[ "$output" == *"exit 2" ]]
}

@test "defaults apply when options are absent" {
    GLOSA_DUMP="output port _v name file"
    glosa_both "$FEAT" a.txt
    [ "$output" = "exit=0
output=out.txt
port=8080
_v=0
name[]=0
file=a.txt" ]
}

@test "list default is split on spaces" {
    GLOSA_DUMP="tag"
    glosa_both 'Usage: prog [--tag=<t>...]

Options:
  --tag=<t>  Tags [default: a b]'
    [ "$output" = "exit=0
tag[]=2
tag[0]=a
tag[1]=b" ]
}

@test "hostile caller environment" {
    run "$GLOSA_TEST_BASH" -c '
        set -euo pipefail
        IFS=$'"'"'\n'"'"'
        set -f
        shopt -s nullglob failglob nocasematch
        source "$1"
        glosa::parse "$2" c s "*" "a b"
        printf "%s|%s|%s\n" "${#args[@]}" "${args[0]}" "${args[1]}"
        [[ "$-" == *e* && "$-" == *u* && "$-" == *f* ]] && shopt -q nocasematch && echo restored
    ' _ "$GLOSA" "$DISPATCHER"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "2|*|a b" ]
    [ "${lines[1]}" = "restored" ]
}

@test "commands match case-sensitively even with nocasematch" {
    run "$GLOSA_TEST_BASH" -c 'shopt -s nocasematch; source "$1"; glosa::parse "$2" LIST_ITEMS' _ "$GLOSA" "$STORE"
    [ "$status" -eq 1 ]
}

@test "no external commands are needed" {
    run "$GLOSA_TEST_BASH" -c 'source "$1"; PATH=/nonexistent; glosa::parse "$2" c s x; echo "${args[0]}"' _ "$GLOSA" "$DISPATCHER"
    [ "$status" -eq 0 ]
    [ "$output" = "x" ]
}

@test "glosa.sh has no command substitutions, backticks or pipes" {
    # "$((" is arithmetic, not a subshell.
    run grep -nE '\$\([^(]|`| \| ' <(grep -vE '^[[:space:]]*#' "$GLOSA")
    [ "$status" -eq 1 ]
}

# Prints a UTF-8 locale this system has: neither en_US.UTF-8 nor C.UTF-8
# exists everywhere.
utf8_locale() {
    locale -a 2>/dev/null | grep -m1 -iE '^(en_US|C)\.utf-?8$'
}

@test "the caller's locale is untouched and non-ASCII values survive" {
    local loc
    loc="$(utf8_locale)" || skip "no UTF-8 locale"
    run env LANG="$loc" LC_ALL="$loc" "$GLOSA_TEST_BASH" -c '
        source "$1"
        glosa::parse "$2" "año ñu"
        x="é"
        echo "${#x}|$LC_ALL|$text"
        eval "$("$BASH" "$1" -h "$2" : "café")"
        echo "$text"
    ' _ "$GLOSA" "$SAY"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1|$loc|año ñu" ]
    [ "${lines[1]}" = "café" ]
}

@test "help text with a tilde is printed literally" {
    local help='Usage: prog <x>

Reads ~/.config and a:~/x'
    GLOSA_DUMP=""
    glosa_both "$help" -h
    [ "$(< "$BATS_TEST_TMPDIR/out.cli")" = "$help" ]
    [ "$(< "$BATS_TEST_TMPDIR/out.src")" = "$help" ]
}

@test "default on a continuation line of an option description" {
    GLOSA_DUMP="output"
    glosa_both 'Usage: p [options]

Options:
  -o FILE, --output FILE  Output file
                          [default: out.txt]'
    [ "$output" = "exit=0
output=out.txt" ]
}

@test "a fully indented help with whitespace-only blank lines" {
    GLOSA_DUMP="x quiet"
    glosa_both "    Usage:
      p <x> [--quiet]
    
    Options:
      -q --quiet  Quiet" a -q
    [ "$output" = "exit=0
x=a
quiet=true" ]
}

@test "on exit paths the caller's EXIT trap sees the caller's shell state" {
    # LC_ALL is cleared first: CI runners export it.
    run env -u LC_ALL "$GLOSA_TEST_BASH" -c '
        trap '"'"'echo "trap:$-:${LC_ALL-unset}"'"'"' EXIT
        source "$1"
        glosa::parse "Usage: p <x>"
    ' _ "$GLOSA"
    [ "$status" -eq 1 ]
    [[ "${lines[${#lines[@]}-1]}" == trap:* ]]
    [[ "${lines[${#lines[@]}-1]}" != trap:*f*:* ]]
    [[ "${lines[${#lines[@]}-1]}" == *:unset ]]
}
