#!/usr/bin/env bash

set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '==> %s\n' "$*"
}

load_profile() {
    local repo_root="$1"

    local dell_conf="$repo_root/profiles/dell.conf"
    local features_conf="$repo_root/profiles/features.conf"

    [[ -f "$dell_conf" ]] ||
        die "Missing profile file: $dell_conf"

    [[ -f "$features_conf" ]] ||
        die "Missing feature file: $features_conf"

    # shellcheck source=/dev/null
    source "$dell_conf"

    # shellcheck source=/dev/null
    source "$features_conf"

    info "Loaded profile: ${PROFILE_NAME:-unknown} v${PROFILE_VERSION:-unknown}"
}

validate_profile() {
    [[ -n "${PROFILE_NAME:-}" ]] ||
        die "PROFILE_NAME must not be empty."

    [[ -n "${PROFILE_VERSION:-}" ]] ||
        die "PROFILE_VERSION must not be empty."

    [[ "${PROCESSOR_OPT:-}" == "native" ]] ||
        die "Unsupported PROCESSOR_OPT: ${PROCESSOR_OPT:-unset}"

    case "${TICKRATE:-}" in
        idle|full|periodic)
            ;;
        *)
            die "Invalid TICKRATE: ${TICKRATE:-unset}"
            ;;
    esac

    case "${DEFAULT_KEEP_KVM:-}" in
        yes|no)
            ;;
        *)
            die "DEFAULT_KEEP_KVM must be yes or no."
            ;;
    esac

    case "${DEFAULT_KEEP_INTEL_TDX:-}" in
        yes|no)
            ;;
        *)
            die "DEFAULT_KEEP_INTEL_TDX must be yes or no."
            ;;
    esac

    case "${DEFAULT_KEEP_AMD_SEV:-}" in
        yes|no)
            ;;
        *)
            die "DEFAULT_KEEP_AMD_SEV must be yes or no."
            ;;
    esac

    case "${DEFAULT_KEEP_NVME_FABRICS:-}" in
        yes|no)
            ;;
        *)
            die "DEFAULT_KEEP_NVME_FABRICS must be yes or no."
            ;;
    esac

    case "${DEFAULT_KEEP_NVME_TARGET:-}" in
        yes|no)
            ;;
        *)
            die "DEFAULT_KEEP_NVME_TARGET must be yes or no."
            ;;
    esac

    case "${DEFAULT_KERNEL_HZ:-}" in
        upstream|100|250|300|1000)
            ;;
        *)
            die "DEFAULT_KERNEL_HZ must be upstream, 100, 250, 300 or 1000."
            ;;
    esac

    # These are part of the universal Dell profile contract and are consumed later
    # by the Kconfig/build validation layer.
    declare -p REQUIRE_ENABLED_BOOL >/dev/null 2>&1 ||
        die "REQUIRE_ENABLED_BOOL must be defined by dell.conf."

    declare -p REQUIRE_DISABLED >/dev/null 2>&1 ||
        die "REQUIRE_DISABLED must be defined by dell.conf."

    declare -p PRESERVE_ENABLED >/dev/null 2>&1 ||
        die "PRESERVE_ENABLED must be defined by dell.conf."
    declare -p PRESERVE_BASELINE_STATE >/dev/null 2>&1 ||
        die "PRESERVE_BASELINE_STATE must be defined by dell.conf."

    declare -p DISABLE_NON_DELL_PLATFORM >/dev/null 2>&1 ||
        die "DISABLE_NON_DELL_PLATFORM must be defined by dell.conf."

    local group symbol
    local -A seen=()
    for group in REQUIRE_ENABLED_BOOL REQUIRE_DISABLED PRESERVE_ENABLED PRESERVE_BASELINE_STATE DISABLE_NON_DELL_PLATFORM; do
        local -n symbols="$group"
        for symbol in "${symbols[@]}"; do
            [[ "$symbol" =~ ^[A-Z0-9_]+$ ]] ||
                die "Invalid Kconfig symbol in $group: $symbol"
            [[ -z "${seen[$symbol]:-}" ]] ||
                die "CONFIG_$symbol occurs in both ${seen[$symbol]} and $group."
            seen["$symbol"]="$group"
        done
    done

    info "Profile values are valid."
}
