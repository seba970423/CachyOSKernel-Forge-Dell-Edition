#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/lib/profile.sh"
source "$REPO_ROOT/lib/hardware.sh"
source "$REPO_ROOT/lib/kconfig.sh"
source "$REPO_ROOT/lib/validate.sh"
TEST_TMPDIR="$(mktemp -d --tmpdir kernelforge-dell-test.XXXXXX)"
trap 'rm -rf -- "$TEST_TMPDIR"' EXIT
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
expect_failure() {
    if ( "$@" ) >/dev/null 2>&1; then fail "Unexpected success: $*"; fi
}
load_profile "$REPO_ROOT" >/dev/null
validate_profile >/dev/null
[[ "$PROFILE_NAME" == dell ]] || fail 'Wrong target profile.'
original_profile="$(declare -p PRESERVE_ENABLED PRESERVE_BASELINE_STATE DISABLE_NON_DELL_PLATFORM)"
dmi="$TEST_TMPDIR/dmi"
mkdir -p "$dmi"
write_dmi() {
    printf '%s\n' "$1" > "$dmi/sys_vendor"
    printf '%s\n' "$2" > "$dmi/product_name"
    printf '%s\n' "$3" > "$dmi/product_family"
    printf '%s\n' "$4" > "$dmi/chassis_type"
    detect_platform "$dmi"
}
write_dmi 'Dell Inc.' 'Latitude 7490' 'Latitude' 9
[[ "$PLATFORM_DELL_LAPTOP" == yes && "$PLATFORM_LATITUDE_7490" == yes ]] ||
    fail 'Latitude 7490 not recognized.'
for product in 'XPS 13 9360' 'Precision 7550' 'Inspiron 15 5515' 'Dell Pro 14'; do
    write_dmi 'Dell Inc.' "$product" unknown 10
    [[ "$PLATFORM_DELL_LAPTOP" == yes && "$PLATFORM_LATITUDE_7490" == no ]] ||
        fail "Portable chassis not recognized: $product"
done
write_dmi 'Alienware' 'Alienware m15' 'Alienware' 10
[[ "$PLATFORM_DELL_LAPTOP" == yes ]] || fail 'Alienware laptop rejected.'
write_dmi 'Dell Computer Corporation' 'Latitude D630' 'Latitude' 8
[[ "$PLATFORM_DELL_LAPTOP" == yes ]] || fail 'Legacy Dell laptop rejected.'
for product in 'OptiPlex 7090' 'Precision 5820 Tower' 'XPS 8940'; do
    write_dmi 'Dell Inc.' "$product" unknown 3
    [[ "$PLATFORM_DELL" == yes && "$PLATFORM_DELL_LAPTOP" == no ]] ||
        fail "Desktop misidentified as laptop: $product"
done
write_dmi LENOVO 'ThinkPad T590' ThinkPad 10
[[ "$PLATFORM_DELL" == no && "$PLATFORM_DELL_LAPTOP" == no ]] ||
    fail 'Non-Dell host misidentified.'
write_dmi 'Dell Inc.' 'Latitude 7490' Latitude 9
rm "$dmi/chassis_type"
detect_platform "$dmi"
[[ "$PLATFORM_DELL_LAPTOP" == yes && "$PLATFORM_LATITUDE_7490" == yes ]] ||
    fail 'Missing chassis field broke Latitude fallback.'
detect_platform "$TEST_TMPDIR/missing"
[[ "$PLATFORM_VENDOR" == unknown && "$PLATFORM_DELL_LAPTOP" == no &&
   "$PLATFORM_LATITUDE_7490" == no ]] || fail 'Missing DMI retained stale state.'
have_cmd() { return 1; }
detect_pci_hardware
[[ "$GPU_INTEL" == unknown && "$THUNDERBOLT_PRESENT" == unknown ]] ||
    fail 'Missing lspci was treated as a complete inventory.'
[[ "$original_profile" == "$(declare -p PRESERVE_ENABLED PRESERVE_BASELINE_STATE DISABLE_NON_DELL_PLATFORM)" ]] ||
    fail 'Host diagnostics modified target support.'

# Conflicting and duplicate rules must abort before source preparation.
(
    PRESERVE_ENABLED+=(DELL_SMBIOS)
    expect_failure validate_profile
)
(
    DISABLE_NON_DELL_PLATFORM+=(DELL_WMI)
    expect_failure validate_profile
)
(
    DISABLE_NON_DELL_PLATFORM+=('NOT-A-SYMBOL')
    expect_failure validate_profile
)
# Required Dell support must not silently vanish during dependency resolution.
reference="$REPO_ROOT/profiles/reference/cachyos-7.2.11-upstream.config"
for symbol in DCDBAS DELL_SMBIOS DELL_SMBIOS_WMI DELL_SMBIOS_SMM DELL_LAPTOP DELL_WMI SENSORS_DELL_SMM MOUSE_PS2_ALPS; do
    cp "$reference" "$TEST_TMPDIR/final.config"
    sed -i -E "s/^CONFIG_${symbol}=[ym]$/# CONFIG_${symbol} is not set/" "$TEST_TMPDIR/final.config"
    expect_failure validate_protected_symbol "$TEST_TMPDIR" "$reference" "$TEST_TMPDIR/final.config" "$symbol"
done
printf 'Dell platform and driver regression tests passed.\n'
