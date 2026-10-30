#!/usr/bin/env bash
# Guarded workaround for a CachyOS 7.3 BORE/EEVDF scheduler source mismatch.
# Operates only on the prepared tree, never on checksum-protected inputs.

kernelforge_apply_sched_compat() {
    local tree="$1"
    local config="$tree/.config"
    local file="$tree/kernel/sched/fair.c"
    local state tmp

    [[ -f "$config" ]] || {
        printf 'ERROR: Scheduler preflight: missing resolved kernel configuration.\n' >&2
        return 1
    }
    if ! grep -qx 'CONFIG_SCHED_BORE=y' "$config"; then
        printf '==> Scheduler preflight: BORE disabled; no workaround needed.\n'
        return 0
    fi
    [[ -f "$file" ]] || {
        printf 'ERROR: Scheduler preflight: missing kernel/sched/fair.c.\n' >&2
        return 1
    }

    # Inspect only the helper definition, not unrelated references or calls.
    # With BORE enabled, the upstream patch declares the normalized variable
    # only under #else, but Linux 7.3.1 still references it in this helper.
    state="$(awk '
        /^[[:space:]]*static[[:space:]]+(inline[[:space:]]+)?void[[:space:]]+update_protect_slice[[:space:]]*\(/ { functions++; remaining=24 }
        remaining > 0 {
            if ($0 ~ /^[[:space:]]*u64 slice = normalized_sysctl_sched_base_slice;[[:space:]]*$/) old++
            if ($0 ~ /^[[:space:]]*u64 slice = sysctl_sched_base_slice;[[:space:]]*$/) new++
            remaining--
        }
        END {
            if (functions == 0) print "missing-function";
            else if (functions != 1) print "unexpected";
            else if (new > 0) print "compatible";
            else if (old == 1) print "patch";
            else print "unexpected";
        }
    ' "$file")" || return 1

    case "$state" in
        compatible)
            printf '==> Scheduler preflight: upstream BORE slice is already compatible.\n'
            return 0
            ;;
        missing-function)
            printf '==> Scheduler preflight: affected helper absent; nothing to patch.\n'
            return 0
            ;;
        patch) ;;
        *)
            printf 'ERROR: Scheduler preflight: unknown update_protect_slice() layout; refusing to patch.\n' >&2
            return 1
            ;;
    esac

    if ! grep -Eq '^[[:space:]]*(__read_mostly[[:space:]]+)?(unsigned int|uint)[[:space:]]+sysctl_sched_base_slice[[:space:]]*=' "$file"; then
        printf 'ERROR: Scheduler preflight: BORE slice variable declaration not found.\n' >&2
        return 1
    fi

    tmp="$(mktemp "${file}.kernelforge.XXXXXX")" || return 1
    if ! awk '
        /^[[:space:]]*static[[:space:]]+(inline[[:space:]]+)?void[[:space:]]+update_protect_slice[[:space:]]*\(/ { remaining=24 }
        remaining > 0 && /^[[:space:]]*u64 slice = normalized_sysctl_sched_base_slice;[[:space:]]*$/ {
            count++
            match($0, /^[[:space:]]*/)
            indent=substr($0, 1, RLENGTH)
            print indent "#ifdef CONFIG_SCHED_BORE"
            print indent "/* KernelForge: CachyOS 7.3 BORE slice compatibility. */"
            print indent "u64 slice = sysctl_sched_base_slice;"
            print indent "#else"
            print $0
            print indent "#endif"
            remaining--
            next
        }
        { print; if (remaining > 0) remaining-- }
        END { if (count != 1) exit 42 }
    ' "$file" > "$tmp"; then
        rm -f -- "$tmp"
        printf 'ERROR: Scheduler preflight: guarded source replacement failed.\n' >&2
        return 1
    fi
    chmod --reference="$file" "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv -- "$tmp" "$file" || return 1
    printf '==> Scheduler preflight: applied guarded BORE slice fix to prepared fair.c.\n'
}

kernelforge_sched_smoke_test() {
    local tree="$1" log="$2"
    [[ -f "$tree/.config" ]] || return 1
    if ! grep -qx 'CONFIG_SCHED_BORE=y' "$tree/.config"; then
        return 0
    fi
    printf '==> Compiling scheduler object before full kernel build...\n'
    printf '==> Scheduler smoke-test log: %s\n' "$log"
    local -a flags=()
    if grep -qx 'CONFIG_CC_IS_CLANG=y' "$tree/.config"; then
        flags=(CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1)
    fi
    if ! make -C "$tree" "${flags[@]}" -j1 kernel/sched/fair.o >"$log" 2>&1; then
        printf 'ERROR: Scheduler smoke test failed before full compilation.\n' >&2
        kernelforge_show_build_errors "$log"
        return 1
    fi
    printf '==> Scheduler object compiled successfully.\n'
}

kernelforge_show_build_errors() {
    local log="$1"
    [[ -f "$log" ]] || return 1
    printf '%s\n' '--- First compiler/build errors ---' >&2
    if ! grep -nEi -m 8 -B 4 -A 6 \
        '(^|[[:space:]])(fatal error:|error:)|undefined reference|no space left on device|killed signal|out of memory|Error [1-9][0-9]*' \
        "$log" >&2; then
        printf 'No recognizable compiler error found; showing log tail instead.\n' >&2
        tail -n 120 "$log" >&2 || true
    fi
    printf '==> Full diagnostics retained: %s\n' "$log" >&2
}
