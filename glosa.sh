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
