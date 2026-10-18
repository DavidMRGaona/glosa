# shellcheck shell=bash
# shellcheck disable=SC2154 # $output and $status are set by bats `run`
# Shared helpers for the bats suite.

GLOSA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOSA="$GLOSA_ROOT/glosa.sh"
GLOSA_TEST_BASH="${GLOSA_TEST_BASH:-bash}"
GLOSA_RUN_CASE="$GLOSA_ROOT/test/support/run_case.bash"
export GLOSA GLOSA_TEST_BASH

# Runs glosa in one mode (cli or src) and leaves the canonical dump in $output.
# Set GLOSA_DUMP to the space-separated variable names to dump.
glosa_case() {
    local mode="$1"
    shift
    GLOSA_OUT="$BATS_TEST_TMPDIR/out.$mode"
    GLOSA_ERR="$BATS_TEST_TMPDIR/err.$mode"
    export GLOSA_OUT GLOSA_ERR GLOSA_DUMP
    run "$GLOSA_TEST_BASH" "$GLOSA_RUN_CASE" "$mode" "$@"
}

# Runs both modes, fails if their dumps or exit codes differ, and leaves the
# result in $output/$status. stdout/stderr of each mode land in
# $BATS_TEST_TMPDIR/{out,err}.{cli,src}.
glosa_both() {
    local cli_output cli_status
    glosa_case cli "$@"
    cli_output="$output"
    cli_status="$status"
    glosa_case src "$@"
    if [[ "$cli_output" != "$output" || "$cli_status" != "$status" ]]; then
        printf 'cli (status %s):\n%s\nsrc (status %s):\n%s\n' \
            "$cli_status" "$cli_output" "$status" "$output" >&2
        return 1
    fi
}

# Escapes a value the same way run_case.bash does.
glosa_esc() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//$'\n'/\\n}"
    printf '%s' "$v"
}
