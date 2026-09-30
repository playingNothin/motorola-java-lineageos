# LineageOS 18.1 — Moto G20 (XT2128-1, codename java)

Unofficial LineageOS 18.1 for the Motorola Moto G20 (Unisoc UMS512 /
Tiger T700, sharkl5pro).

## Status

Working: baseband (data), WiFi, Bluetooth, touch, display, GPU, camera,
sensors, GPS.
Untested: FM (sprd_fm).
Known issue: Bluetooth audio routes to the speaker instead of earbuds
(audio-policy level, unrelated to the BT transport driver).

Both radio drivers are **reconstructions** from the stock binaries (no
public source exists) and are hardware-validated end-to-end:

- `sprdwl_ng` — WiFi (HAL load → probe → CP2 boot → config download →
  wlan0 → supplicant → DHCP → internet)
- `sprdbt_tty` — Bluetooth HCI transport (HAL load → ttyBT0 → HCI → scan)

They load as modules from the preserved `socko` vendor-module partition,
exactly like the stock system: init stages the module, the vendor HAL
loads it with `finit_module()`. The canary system
(`device/motorola/java/rootdir/bin/module_fallback.sh`) tracks per-module
health on the misc partition and can fall back to the stock binaries.

## Repos layout

    device/motorola/java/     LineageOS device tree
    vendor/motorola/java/     vendor extraction makefiles
    kernel/motorola/java/     kernel source (4.14.193, stock-parity)
    reconstructions/          full sources of the reconstructed drivers
                              (sprd_fm-source: UNTESTED)

The kernel builds with symbol-CRC parity against the stock boot image
(scripts/gcc-goto.sh pins the asm-goto detection to match the vendor
build), so every stock module on the socko partition (mali_gondul GPU,
camera, sensors, touch, …) loads unmodified.

## Building the ROM

1. LineageOS 18.1 tree, sources in place:
   - `device/motorola/java` ← this repo's `device/motorola/java`
   - `vendor/motorola/java` ← this repo's `vendor/motorola/java`
   - `kernel/motorola/java` ← this repo's `kernel/motorola/java`
2. `source build/envsetup.sh && lunch lineage_java-userdebug`
3. `m bacon` (the kernel ships prebuilt via
   `device/motorola/java/prebuilt/kernel/Image`; see below)

## Building the kernel

The kernel is 4.14 (kernel version), built with the LineageOS prebuilt
toolchains: GCC **4.9** (that is the toolchain version in the path below,
not the kernel version) as CROSS_COMPILE plus clang r383902 as CC.

From the root of your LineageOS tree:

```bash
LINEAGE=$PWD
cd kernel/motorola/java

export CROSS_COMPILE=$LINEAGE/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
export CC=$LINEAGE/prebuilts/clang/host/linux-x86/clang-r383902/bin/clang
export ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu

# configure (stock config + reconstructed drivers as modules)
make O=out_k CROSS_COMPILE=$CROSS_COMPILE CC=$CC java_defconfig

# build kernel Image and the sprdwl_ng / sprdbt_tty modules
make O=out_k CROSS_COMPILE=$CROSS_COMPILE CC=$CC -j$(nproc) Image modules
```

`out_k/arch/arm64/boot/Image` is the kernel;
`out_k/drivers/net/wireless/sprd/*/` contain the built `.ko` modules.

`java_defconfig` is the stock configuration with the reconstructed
drivers enabled as modules (`CONFIG_SPRDWL_NG=m`,
`CONFIG_SPRDBT_TTY=m`) — anything else must stay as shipped or the
stock socko modules stop loading.

Then either point `TARGET_PREBUILT_KERNEL` at the new Image (already the
default: `device/motorola/java/prebuilt/kernel/Image`) and rebuild the
boot image, or flash `out_k/arch/arm64/boot/Image` through your own
packaging. The driver modules land in
`device/motorola/java/radio_modules/recon/` and are staged onto socko by
the canary at boot.

## Notes

- Keep `persist.vendor.eng.sprdwl` unset: it preloads the WiFi module at
  init, and the HAL treats its own `finit_module()` EEXIST as a failure.
- The radio HALs must be the ones loading the drivers; preloading from
  init works only for sprdbt_tty/fm (wcn.rc), not for sprdwl_ng.
