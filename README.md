# LineageOS 18.1 — Moto G20

Unofficial LineageOS 18.1 build for the Moto G20 (java).

Works: baseband, WiFi, BT, touch, display, camera, sensors, GPS.
Doesn't work: BT audio routes to speaker instead of earbuds.

The WiFi and BT drivers have no public source so they were reconstructed
from the stock binaries. Sources are in `reconstructions/`. They load as
modules from the socko partition.

Don't build them into the kernel. It bootloops. Read `reconstructions/WARNING.md`.

## Build

Standard LineageOS 18.1 tree, drop this in `device/motorola/java`, kernel
in `kernel/motorola/java`, run `extract-files.sh` against the phone, build.
