# LineageOS 18.1 for the Moto G20

Unofficial LineageOS build for the Moto G20 (java). Unisoc UMS512, sharkl5pro.

Baseband, WiFi, Bluetooth, touch, display, camera, sensors and GPS all work.
Not perfect, but daily-drivable.

## The WiFi and BT drivers

These don't have public source code, so they were reconstructed from the
stock binaries. Full sources are in `reconstructions/`. They run as loadable
modules from the socko partition, loaded at boot by the HAL.

The WiFi driver was stress-tested: association, DHCP, internet traffic,
scans — everything matches stock behavior. The BT transport handles HCI,
pairing and profile negotiation fine.

**Do not build these as built-in (`=y`).** They crash the kernel during
init because the probes try to talk to the CP2 chip before it's powered.
Build them as modules (`=m`) or just use the prebuilt ones from socko.
Recovery and fastboot become unreachable if you get this wrong, and you'll
need a test point or ResearchDownload to get back in.

## What doesn't work

BT audio goes through the speaker instead of earbuds. The A2DP device
gets rejected by the audio policy manager when the framework tries to
connect it. The stock Unisoc audio HAL does something different that
AOSP's AudioPolicyManager doesn't handle. I have a rough idea of where
it fails but haven't fixed it yet.

## Building

Drop this in `device/motorola/java` inside a LineageOS 18.1 tree, put the
kernel in `kernel/motorola/java`, extract proprietary files, and build
like any other device. The prebuilt kernel Image is in
`prebuilt/kernel/Image`.

The WiFi/BT module sources are also integrated in-tree at
`drivers/net/wireless/sprd/` (built as modules, loaded from socko).
