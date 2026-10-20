#!/usr/bin/env bash

set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '==> %s\n' "$*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

detect_cpu() {
    CPU_VENDOR_RAW="$(awk -F ': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo)"
    CPU_MODEL="$(awk -F ': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)"

    case "$CPU_VENDOR_RAW" in
        GenuineIntel)
            CPU_VENDOR="intel"
            ;;
        AuthenticAMD)
            CPU_VENDOR="amd"
            ;;
        *)
            CPU_VENDOR="unknown"
            ;;
    esac

    if grep -qw vmx /proc/cpuinfo; then
        CPU_HAS_VMX="yes"
    else
        CPU_HAS_VMX="no"
    fi

    if grep -qw svm /proc/cpuinfo; then
        CPU_HAS_SVM="yes"
    else
        CPU_HAS_SVM="no"
    fi

    return 0
}

detect_pci_hardware() {
    GPU_INTEL="unknown"
    GPU_AMD="unknown"
    GPU_NVIDIA="unknown"
    WIFI_INTEL="unknown"
    THUNDERBOLT_PRESENT="unknown"
    NVME_PRESENT="unknown"

    # PCI inventory is diagnostic only and must not become a hard dependency
    # or influence the universal Dell allowlist.
    if ! have_cmd lspci; then
        return 0
    fi

    PCI_DUMP="$(lspci -nn)"

    GPU_INTEL="no"
    GPU_AMD="no"
    GPU_NVIDIA="no"
    WIFI_INTEL="no"
    THUNDERBOLT_PRESENT="no"
    NVME_PRESENT="no"

    # Scope GPU vendor detection strictly to display-class PCI devices.
    # This avoids false positives from Intel chipsets, SATA controllers, etc.
    GPU_DUMP="$(grep -Ei 'VGA compatible controller|3D controller|Display controller' <<<"$PCI_DUMP" || true)"

    if [[ -n "$GPU_DUMP" ]]; then
        # Use PCI vendor IDs instead of names. A loose case-insensitive "ATI"
        # match also matches the word "compatible" in every VGA description.
        grep -Eqi '\[8086:[[:xdigit:]]{4}\]' <<<"$GPU_DUMP" && GPU_INTEL="yes" || true
        grep -Eqi '\[1002:[[:xdigit:]]{4}\]' <<<"$GPU_DUMP" && GPU_AMD="yes" || true
        grep -Eqi '\[10de:[[:xdigit:]]{4}\]' <<<"$GPU_DUMP" && GPU_NVIDIA="yes" || true
    fi

    if grep -Ei 'Network controller|Wireless' <<<"$PCI_DUMP" | grep -qi 'Intel'; then
        WIFI_INTEL="yes"
    fi

    # PCI descriptions vary across generations; accept both names.
    if grep -Eqi 'Thunderbolt|USB4' <<<"$PCI_DUMP"; then
        THUNDERBOLT_PRESENT="yes"
    fi

    # Prefer PCI-class detection, but also accept a populated sysfs NVMe class.
    if grep -qi 'Non-Volatile memory controller' <<<"$PCI_DUMP" ||
        compgen -G '/sys/class/nvme/nvme*' >/dev/null; then
        NVME_PRESENT="yes"
    fi

    return 0
}

detect_platform() {
    # Optional path is for offline DMI fixtures; production uses kernel sysfs.
    local dmi_root="${1:-/sys/class/dmi/id}"
    local vendor
    PLATFORM_VENDOR="unknown"
    PLATFORM_PRODUCT="unknown"
    PLATFORM_FAMILY="unknown"
    PLATFORM_CHASSIS="unknown"
    PLATFORM_DELL="no"
    PLATFORM_DELL_LAPTOP="no"
    PLATFORM_LATITUDE_7490="no"

    if [[ -r "$dmi_root/sys_vendor" ]]; then
        PLATFORM_VENDOR="$(< "$dmi_root/sys_vendor")"
    fi
    if [[ -r "$dmi_root/product_name" ]]; then
        PLATFORM_PRODUCT="$(< "$dmi_root/product_name")"
    fi
    if [[ -r "$dmi_root/product_family" ]]; then
        PLATFORM_FAMILY="$(< "$dmi_root/product_family")"
    fi
    if [[ -r "$dmi_root/chassis_type" ]]; then
        PLATFORM_CHASSIS="$(< "$dmi_root/chassis_type")"
    fi

    vendor="${PLATFORM_VENDOR,,}"
    case "$vendor" in
        dell|"dell inc."|"dell computer corporation"|alienware|"alienware corporation")
            PLATFORM_DELL="yes"
            ;;
    esac
    if [[ "$PLATFORM_DELL" == yes ]]; then
        # SMBIOS portable, laptop, notebook, subnotebook, tablet, convertible,
        # detachable. A Dell desktop is not identified as a laptop.
        case "$PLATFORM_CHASSIS" in
            8|9|10|14|30|31|32) PLATFORM_DELL_LAPTOP="yes" ;;
            unknown)
                # Latitude is unambiguously a portable family even when
                # firmware omits its chassis field.
                if [[ "${PLATFORM_PRODUCT,,}" == latitude* ]]; then
                    PLATFORM_DELL_LAPTOP="yes"
                fi
                ;;
        esac
        if [[ "$PLATFORM_DELL_LAPTOP" == yes &&
              "${PLATFORM_PRODUCT,,}" == "latitude 7490" ]]; then
            PLATFORM_LATITUDE_7490="yes"
        fi
    fi
    return 0
}

print_hardware_summary() {
    info "CPU vendor: ${CPU_VENDOR:-unknown}"
    info "CPU model: ${CPU_MODEL:-unknown}"
    info "Intel VT-x/VMX: ${CPU_HAS_VMX:-no}"
    info "AMD-V/SVM: ${CPU_HAS_SVM:-no}"

    info "Intel GPU detected: ${GPU_INTEL:-no}"
    info "AMD GPU detected: ${GPU_AMD:-no}"
    info "NVIDIA GPU detected: ${GPU_NVIDIA:-no}"

    info "Intel Wi-Fi detected: ${WIFI_INTEL:-no}"
    info "Thunderbolt/USB4 detected: ${THUNDERBOLT_PRESENT:-no}"
    info "NVMe controller detected: ${NVME_PRESENT:-no}"

    info "Platform vendor: ${PLATFORM_VENDOR:-unknown}"
    info "Platform product: ${PLATFORM_PRODUCT:-unknown}"
    info "Platform family: ${PLATFORM_FAMILY:-unknown}"
    info "SMBIOS chassis type: ${PLATFORM_CHASSIS:-unknown}"
    info "Dell vendor detected: ${PLATFORM_DELL:-no}"
    info "Dell laptop detected: ${PLATFORM_DELL_LAPTOP:-no}"
    info "Latitude 7490 detected: ${PLATFORM_LATITUDE_7490:-no}"

    if [[ "${PLATFORM_DELL_LAPTOP:-no}" != "yes" ]]; then
        printf 'WARNING: The current machine was not identified as a Dell laptop.\n' >&2
        printf 'WARNING: Native CPU optimization targets the current build CPU.\n' >&2
    fi
}

detect_hardware() {
    detect_cpu
    detect_pci_hardware
    detect_platform

    return 0
}
