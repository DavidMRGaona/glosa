#!/usr/bin/env bats
# shellcheck shell=bats
#
# Reference fixtures: real-world usage blocks with their expected outcome.
# Each test/fixtures/<case>/ holds:
#   help         help text
#   argv         one argument per line ("\n" = newline, "\\" = backslash)
#   expected     "exit=<n>" plus canonical variable lines (see run_case.bash)
#   stdout       (optional) exact stdout, for -h cases
#   stderr_tail  (optional) text stderr must end with, for usage errors
#
# Set GLOSA_FIXTURES to run another fixture directory with the same format.

load test_helper

_unesc() {
    local s="$1" r="" c
    while [[ -n "$s" ]]; do
        c="${s:0:1}"
        s="${s:1}"
        if [[ "$c" == "\\" ]]; then
            c="${s:0:1}"
            s="${s:1}"
            if [[ "$c" == "n" ]]; then r+=$'\n'; else r+="$c"; fi
        else
            r+="$c"
        fi
    done
    _unesc_result="$r"
}

_check_fixture() {
    local mode="$1" dir="$2" line expected help err tail
    local -a args=()
    while IFS= read -r line; do
        _unesc "$line"
        args+=("$_unesc_result")
    done < "$dir/argv"
    help="$(< "$dir/help")"
    expected="$(< "$dir/expected")"
    # shellcheck disable=SC2034 # read by glosa_case
    GLOSA_DUMP="$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)\(\[\]\)\{0,1\}=.*/\1/p' "$dir/expected" | sed '/^exit$/d' | tr '\n' ' ')"
    glosa_case "$mode" "$help" ${args[@]+"${args[@]}"}
    if [[ "$output" != "$expected" ]]; then
        printf 'state differs:\n--- expected\n%s\n--- got\n%s\n' "$expected" "$output"
        return 1
    fi
    if [[ -f "$dir/stdout" ]] && [[ "$(< "$GLOSA_OUT")" != "$(< "$dir/stdout")" ]]; then
        printf 'stdout differs:\n%s\n' "$(< "$GLOSA_OUT")"
        return 1
    fi
    if [[ -f "$dir/stderr_tail" ]]; then
        err="$(< "$GLOSA_ERR")"
        tail="$(< "$dir/stderr_tail")"
        if [[ "$err" != *"$tail" ]]; then
            printf 'stderr does not end with the usage block:\n%s\n' "$err"
            return 1
        fi
    fi
}

_run_all() {
    local mode="$1" dir failed=0 report
    for dir in "${GLOSA_FIXTURES:-$GLOSA_ROOT/test/fixtures}"/*/; do
        dir="${dir%/}"
        if ! report="$(_check_fixture "$mode" "$dir")"; then
            printf '# FAIL %s\n%s\n' "${dir##*/}" "$report" | head -20
            failed=$((failed + 1))
        fi
    done
    printf '# %s: %d failing fixture(s)\n' "$mode" "$failed"
    [[ "$failed" -eq 0 ]]
}

@test "fixtures: eval mode (CLI)" {
    _run_all cli
}

@test "fixtures: source mode" {
    _run_all src
}
