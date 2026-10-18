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
    local _rc_rc="$1" _rc_name _rc_decl _rc_i _rc_len _rc_ref
    trap - EXIT
    set +eu
    exec 1>&3 2>&4
    printf 'exit=%s\n' "$_rc_rc"
    for _rc_name in ${GLOSA_DUMP:-}; do
        _rc_decl="$(declare -p "$_rc_name" 2>/dev/null)"
        if [[ -z "$_rc_decl" ]]; then
            printf '%s=<unset>\n' "$_rc_name"
        elif [[ "$_rc_decl" == "declare -a"* ]]; then
            eval "_rc_len=\${#${_rc_name}[@]}"
            printf '%s[]=%s\n' "$_rc_name" "$_rc_len"
            _rc_i=0
            while (( _rc_i < _rc_len )); do
                # Indirect expansion, not eval: Bash 3.2's eval mangles \001.
                _rc_ref="${_rc_name}[$_rc_i]"
                printf '%s[%s]=%s\n' "$_rc_name" "$_rc_i" "$(_rc_esc "${!_rc_ref}")"
                _rc_i=$((_rc_i + 1))
            done
        else
            printf '%s=%s\n' "$_rc_name" "$(_rc_esc "${!_rc_name}")"
        fi
    done
    exit "$_rc_rc"
}

_rc_mode="$1"
_rc_help="$2"
shift 2

exec 3>&1 4>&2 1>"${GLOSA_OUT:-/dev/null}" 2>"${GLOSA_ERR:-/dev/null}"
trap '_rc_dump $?' EXIT

case "$_rc_mode" in
    cli)
        _rc_code="$("${GLOSA_TEST_BASH:-bash}" "$GLOSA" -h "$_rc_help" : "$@")" || true
        eval "$_rc_code"
        ;;
    src)
        # shellcheck source=/dev/null
        source "$GLOSA"
        glosa::parse "$_rc_help" "$@"
        ;;
    *)
        printf 'run_case: unknown mode %s\n' "$_rc_mode" >&2
        exit 99
        ;;
esac
