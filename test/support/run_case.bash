# shellcheck shell=bash
# Runs glosa in a fresh shell and prints the resulting state canonically.
#
# usage: run_case.bash <cli|src> <help> [args...]
#
# Output: "exit=<n>" followed, for every name in $GLOSA_DUMP, by
# "name=<esc>" (scalars) or "name[]=<len>" and "name[<i>]=<esc>" (arrays).
# <esc> escapes "\" as "\\" and newlines as "\n". Variables that are not set
# print "name=<unset>". glosa's stdout/stderr go to $GLOSA_OUT/$GLOSA_ERR.

set -euo pipefail

_rc_esc() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//$'\n'/\\n}"
    printf '%s' "$v"
}

_rc_dump() {
    local rc="$1" name decl i len
    trap - EXIT
    set +eu
    exec 1>&3 2>&4
    printf 'exit=%s\n' "$rc"
    for name in ${GLOSA_DUMP:-}; do
        decl="$(declare -p "$name" 2>/dev/null)"
        if [[ -z "$decl" ]]; then
            printf '%s=<unset>\n' "$name"
        elif [[ "$decl" == "declare -a"* ]]; then
            eval "len=\${#${name}[@]}"
            printf '%s[]=%s\n' "$name" "$len"
            i=0
            while (( i < len )); do
                eval "printf '%s[%s]=%s\n' \"\$name\" \"\$i\" \"\$(_rc_esc \"\${${name}[$i]}\")\""
                i=$((i + 1))
            done
        else
            printf '%s=%s\n' "$name" "$(_rc_esc "${!name}")"
        fi
    done
    exit "$rc"
}

mode="$1"
help="$2"
shift 2

exec 3>&1 4>&2 1>"${GLOSA_OUT:-/dev/null}" 2>"${GLOSA_ERR:-/dev/null}"
trap '_rc_dump $?' EXIT

case "$mode" in
    cli)
        _rc_code="$("${GLOSA_TEST_BASH:-bash}" "$GLOSA" -h "$help" : "$@")" || true
        eval "$_rc_code"
        ;;
    src)
        # shellcheck source=/dev/null
        source "$GLOSA"
        glosa::parse "$help" "$@"
        ;;
    *)
        printf 'run_case: unknown mode %s\n' "$mode" >&2
        exit 99
        ;;
esac
