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
