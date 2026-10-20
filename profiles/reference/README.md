# Regression fixture provenance

`cachyos-7.2.11-upstream.config` is an unchanged upstream CachyOS
`linux-cachyos/config`, captured on 2026-10-20 from commit
`08c3d8b0941096e855e3a478f49497cd3f708a21`.

Source: https://github.com/CachyOS/linux-cachyos/blob/08c3d8b0941096e855e3a478f49497cd3f708a21/linux-cachyos/config

This broad upstream configuration exercises the Dell profile's preservation
contract in offline unit tests. It is not a configuration captured from a Dell
Latitude 7490, nor evidence that a Dell kernel has compiled or booted.
Production builds normalize the selected variant's own configuration and
validate it against that baseline; this fixture is never used to build a kernel.
