# KernelForge Dell Edition

A custom x86-64 kernel builder for Dell laptops running Arch Linux, CachyOS,
or another Arch-based distribution. This edition adapts the ThinkPad builder's
validated configuration pipeline to Dell firmware and hardware, with the
Latitude 7490 as the first model covered by detection fixtures.

Derived from [KernelForge ThinkPad Edition](https://github.com/seba970423/CachyOSKernel-Forge-Thinkpad-Edition), with a separate Dell hardware profile and its own release history.

## Hardware contract

The target is the Dell laptop family: Latitude, XPS, Inspiron, Vostro,
Precision mobile workstations, Dell Pro and Alienware laptops. Detection is
diagnostic; support is never trimmed to the build host's inventory.

- Preserve Dell SMBIOS and both its WMI and SMM backends, DCDBAS, Dell laptop
  extras, WMI hotkeys and descriptors, airplane-mode controls, supported
  platform profiles, sensor interfaces and firmware settings.
- Preserve Alienware WMI interfaces and the Compal support used by some older
  Dell models.
- Preserve the complete upstream Dell firmware configuration group, including
  optional privacy functions and drivers added in later kernel versions.
- Preserve ACPI, batteries, thermal management, CPU frequency/idle, suspend,
  display brightness, TPM, audio, cameras and card readers.
- Preserve Intel and AMD CPUs, Intel/AMD graphics, Nouveau, and the foundations
  used by hybrid graphics. Proprietary NVIDIA modules still require the
  appropriate external driver and matching kernel headers.
- Preserve PS/2 ALPS, Synaptics, TrackPoint and Elantech support, I2C HID,
  multitouch and Synaptics RMI transports/functions.
- Preserve NVMe and SATA/AHCI, USB storage, Intel/AMD/other Wi-Fi foundations,
  Bluetooth, Ethernet, USB-C/UCSI, Thunderbolt/USB4 and dock networking.
- Preserve consumer HID devices and USB/Bluetooth gaming controllers.
- Remove audited firmware/platform drivers for other computer families,
  including Lenovo/ThinkPad. Vendor-named detachable peripherals are retained.

Drivers expose only functions supported by a particular machine's firmware.
Including Dell freefall support does not imply the Latitude 7490 contains
a freefall sensor. Sensor and firmware interfaces are retained without forcing
module loading, changing BIOS settings, taking over fan control, or overriding
CPU power limits.

A native build is optimized for the processor performing the build. Run this
on the intended Dell laptop; the builder supports different Dell models, but a
package compiled for one CPU is not a universal binary for every Dell.

## Latitude 7490

The profile explicitly protects the Dell firmware stack, Intel i915,
Intel power/thermal interfaces, Realtek HDA audio, Intel Wi-Fi, Ethernet, NVMe,
the ALPS/PS2 and I2C input paths, and USB-C/Thunderbolt support relevant to this
generation. It also retains alternative components for other configurations.
It does not assume that every 7490 has identical options or peripherals.

DMI diagnostics recognize Dell and legacy Dell vendor strings, Alienware,
portable/convertible chassis types and the Latitude 7490. Desktop chassis are
not labeled as laptops. Missing DMI or `lspci` information never disables
target support.

## Build

Use an ordinary user account with an Arch-based build environment. The builder
uses `makepkg` and `pacman`; Debian/MX packaging needs a separate adaptation.
The foundational build commands must already be available. Package-specific
dependencies are offered through pacman during source preparation.

```bash
git clone https://github.com/seba970423/CachyOSKernel-Forge-Dell-Edition.git
cd CachyOSKernel-Forge-Dell-Edition
./builder-dry-run.sh
```

The dry-run downloads/prepares sources and validates their resolved
configuration. It does not compile or install a kernel. For the complete
workflow:

```bash
./builder.sh
```

Both entry points share source preparation, configuration changes and
validation. The full builder offers compilation and installation separately.
It installs exactly the packages recorded in that build's manifest and never
reboots automatically.

Work trees and compiler temporary files are retained under `/var/tmp`.
Logs and configurations remain available for inspection. The existing optional
post-install cleanup and optional Zstandard-compressed DWARF features are
retained; see [POST-INSTALL-CLEANUP.md](POST-INSTALL-CLEANUP.md).

## Choices retained from the original builder

- Select an available CachyOS kernel variant, including BORE, RT-BORE, LTS,
  Hardened and other variants offered by upstream.
- Keep the upstream package name or explicitly choose a custom name.
  For a separately named Dell build, for example, use `seba-dell-rt-bore`
  when asked for a name without the `linux-` prefix.
- Native CPU optimization and tickless idle are the profile defaults.
- Preserve KVM, Intel TDX/AMD SEV and specialized NVMe roles by default.
  Explicitly declining the corresponding prompt removes that capability;
  ordinary local NVMe and SATA support remain protected.
- Preserve the upstream tick frequency, or choose 100/250/300/1000 Hz when
  supported by the selected source.
- Optional autogrouping is offered only when dependency resolution permits it.
  Alternative schedulers such as BMQ do not get that prompt.
- Optional transparent hugepages use madvise and are offered only on supported
  non-RT configurations.
- Declining optional tuning preserves upstream state. Variant-specific policy,
  including Hardened's disabled hibernation, is respected.
- RT graphics compatibility continues to use CachyOS's upstream i915 patches.

Missing or locally expired signing keys are imported/refreshed automatically
using only the full fingerprints pinned by the selected upstream PKGBUILD.
No import confirmation is needed. Existing usable keys are left alone.
If key retrieval or verification fails, source preparation stops with an error.

Upstream checksums and PGP verification remain active. The validated source
tree is reused for compilation with `makepkg --noextract`.
A required driver disabled in an upstream baseline causes validation to fail;
a driver absent from an older source version is skipped. Any change to an
enabled protected driver or the Dell firmware group also fails validation
before compilation.

Keep a known-good kernel installed until the new build has booted successfully.

## Validation status

The Dell edition adds DMI fixtures covering the Latitude 7490, other Dell
laptop families, Alienware, legacy Dell, desktops and missing firmware data.
Regression tests check profile conflicts, lost Dell drivers, SMBIOS backends,
ALPS input, changed optional/future Dell interfaces and the existing naming,
policy, tuning, validation and cleanup workflows.

```bash
bash tests/run-tests.sh
```

The GitHub Actions workflow runs shell syntax checks and offline regression
tests on pushes to main and pull requests. See the [Actions results](https://github.com/seba970423/CachyOSKernel-Forge-Dell-Edition/actions) for the current status.

The reference configuration is an unchanged upstream CachyOS 7.2.11 packaging
fixture, with provenance in [profiles/reference/README.md](profiles/reference/README.md).
It is not captured Dell hardware data. This Dell edition has not yet been
compiled or boot-tested on a Latitude 7490, and the original ThinkPad edition's
build/boot results do not establish Dell validation.
