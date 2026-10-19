#!/usr/bin/env bats
# shellcheck shell=bats

load test_helper

@test "sourcing defines the public API and version" {
    run "$GLOSA_TEST_BASH" -c "source '$GLOSA'; declare -F glosa::parse; echo \$GLOSA_VERSION"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "glosa::parse" ]
    [ "${lines[1]}" = "0.1.1" ]
}

@test "sourcing does not run the CLI" {
    run "$GLOSA_TEST_BASH" -c "source '$GLOSA'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "CLI without -h <help> : prints its own usage and exits 2" {
    run "$GLOSA_TEST_BASH" "$GLOSA"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage: glosa [--version <version>] -h <help> : [args...]"* ]]
}
