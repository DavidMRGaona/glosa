#!/usr/bin/env bash
# Measures glosa in source mode and in CLI mode on realistic help texts.
#
# usage: bench/bench.sh            (uses hyperfine when available)
#        BENCH_BASH=/bin/bash bench/bench.sh
#
# Each help in bench/helps/<name>.txt is parsed with the arguments listed for
# <name> in bench/helps/args.txt. The help travels in an environment variable
# so reading it costs nothing inside the measured command.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash_bin="${BENCH_BASH:-bash}"
runs="${BENCH_RUNS:-200}"

# Runs <command> $runs times with the chosen bash.
run_loop() {
    local i=0
    while (( i < runs )); do
        "$bash_bin" -c "$1"
        i=$((i + 1))
    done
}

# Prints the mean wall time in milliseconds of running <command> $runs times.
time_loop() {
    local TIMEFORMAT=%R t
    t=$( { time run_loop "$1"; } 2>&1 )
    awk -v t="$t" -v n="$runs" 'BEGIN { printf "%.1f ms\n", t * 1000 / n }'
}

# shellcheck disable=SC2016 # expanded by the measured bash
echo "bash: $("$bash_bin" -c 'echo "$BASH_VERSION"')"
while read -r name args; do
    [[ -z "$name" ]] && continue
    GLOSA_BENCH_HELP="$(< "$root/bench/helps/$name.txt")"
    export GLOSA_BENCH_HELP
    src="source '$root/glosa.sh'; glosa::parse \"\$GLOSA_BENCH_HELP\" $args"
    cli="eval \"\$('$bash_bin' '$root/glosa.sh' -h \"\$GLOSA_BENCH_HELP\" : $args)\""
    if command -v hyperfine >/dev/null 2>&1; then
        hyperfine -N --warmup 10 --runs "$runs" --style basic \
            -n "$name (source)" "$bash_bin -c '$src'" \
            -n "$name (cli)" "$bash_bin -c '$cli'" 2>/dev/null | grep -E '^Benchmark|Time'
    else
        printf '%-12s source %s\n' "$name" "$(time_loop "$src")"
        printf '%-12s cli    %s\n' "$name" "$(time_loop "$cli")"
    fi
done < "$root/bench/helps/args.txt"
