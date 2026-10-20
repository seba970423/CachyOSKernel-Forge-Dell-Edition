#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REFERENCE="$REPO_ROOT/profiles/reference/cachyos-7.2.11-upstream.config"

# shellcheck source=/dev/null
source "$REPO_ROOT/profiles/dell.conf"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validate.sh"

[[ -f "$REFERENCE" ]] || {
    printf 'ERROR: Missing upstream reference config: %s\n' "$REFERENCE" >&2
    exit 1
}

failed=0
declare -A protected_symbols=()
for symbol in "${PRESERVE_ENABLED[@]}"; do
    if [[ -n "${protected_symbols[$symbol]:-}" ]]; then
        printf 'ERROR: Duplicate protected symbol CONFIG_%s.\n' "$symbol" >&2
        failed=1
    fi
    protected_symbols["$symbol"]=1

    state="$(config_state "$REFERENCE" "$symbol")"
    if [[ "$state" != "y" && "$state" != "m" ]]; then
        printf 'ERROR: upstream reference does not enable CONFIG_%s (%s).\n' \
            "$symbol" "$state" >&2
        failed=1
    fi
done


for symbol in "${PRESERVE_BASELINE_STATE[@]}"; do
    if [[ -n "${protected_symbols[$symbol]:-}" ]]; then
        printf 'ERROR: Duplicate protected symbol CONFIG_%s.\n' "$symbol" >&2
        exit 1
    fi
    protected_symbols["$symbol"]=1
done

declare -A removed_symbols=()
for symbol in "${DISABLE_NON_DELL_PLATFORM[@]}"; do
    if [[ -n "${removed_symbols[$symbol]:-}" ]]; then
        printf 'ERROR: Duplicate removal symbol CONFIG_%s.\n' "$symbol" >&2
        failed=1
    fi
    removed_symbols["$symbol"]=1

    if [[ -n "${protected_symbols[$symbol]:-}" ]]; then
        printf 'ERROR: CONFIG_%s is both protected and removed.\n' "$symbol" >&2
        failed=1
    fi

done

(( failed == 0 )) || exit 1

printf 'Dell reference validation passed (%d protected, %d audited removals).\n' \
    "${#protected_symbols[@]}" "${#DISABLE_NON_DELL_PLATFORM[@]}"
