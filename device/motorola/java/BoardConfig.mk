#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/motorola/java

# Platform: Unisoc UMS512 (Tiger T700, sharkl5pro), board p352
TARGET_BOARD_PLATFORM := ums512
TARGET_BOOTLOADER_BOARD_NAME := p352
TARGET_BOARD_INFO_FILE := $(DEVICE_PATH)/boardInfo.txt

# Architecture (zygote64_32: primary arm64, secondary arm)
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_VARIANT := cortex-a55
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT_RUNTIME := cortex-a55

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_VARIANT := cortex-a55
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_USES_64_BIT_BINDER := true

# Bootloader / boot image
TARGET_BOOTLOADER_BOARD_NAME := p352
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x05400000
BOARD_SECOND_OFFSET := 0x00f00000
BOARD_TAGS_OFFSET := 0x00000100
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_CMDLINE := console=ttyS1,115200n8
# The real command line is supplied by the bootloader (verified on device):
#   console=null,115200n8 loglevel=1 init=/init root=/dev/ram0 rw printk.devkmsg=on
#   androidboot.boot_devices=soc/soc:ap-apb/71400000.sdio androidboot.init_fatal_panic=true
#   androidboot.hardware=ums512_1h10 androidboot.dtbo_idx=0 ...
# DTB travels in the v1 recovery_dtbo slot (stock layout, dtb_size field = 0)
# The recovery image rule (build/make/core/Makefile) passes only
# INTERNAL_RECOVERYIMAGE_ARGS + BOARD_RECOVERY_MKBOOTIMG_ARGS to mkbootimg —
# neither carries BOARD_RAMDISK_OFFSET. Without --ramdisk_offset here the
# recovery boot image used the AOSP default 0x1000000, which OVERLAPS the
# 19 MB kernel Image loaded at 0x8000 (spans up to ~0x122AC90): uboot copies
# the ramdisk over kernel code and the boot dies silently at the bootlogo.
# Stock loads the ramdisk at 0x05400000. All offsets must be explicit here.
BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE) --kernel_offset $(BOARD_KERNEL_OFFSET) \
    --ramdisk_offset $(BOARD_RAMDISK_OFFSET) --tags_offset $(BOARD_TAGS_OFFSET)
# --header_version must ALSO ride in BOARD_MKBOOTIMG_ARGS: add_img_to_target_files
# rebuilds the payload's boot image from BOOT/ using the info-dict key
# mkbootimg_args (this one), NOT recovery_mkbootimg_args, and mkbootimg defaults
# to header v0 — a v0 image silently drops the --dtb that BOOT/dtb carries.
# Without this, the OTA payload's boot partition was header v0 with NO dtb
# (boot_b would boot without a device tree after a sideload).
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_RECOVERY_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION) \
    --base $(BOARD_KERNEL_BASE) --kernel_offset $(BOARD_KERNEL_OFFSET) \
    --ramdisk_offset $(BOARD_RAMDISK_OFFSET) --tags_offset $(BOARD_TAGS_OFFSET)
# CRITICAL (2026-09-15, hardware-proven via in-place PBRP field edit): the
# Unisoc uboot REJECTS boot images whose os_patch_level is NEWER than the
# device's stored level (stock = 2023-03): reset right after
# "LOCK FLAG IS: UNLOCK!!!", before "skip verify". Confirmed by flashing the
# proven PBRP image with ONLY the os_version field changed to 2024-02 — it
# bootlooped; with 2022-07 it boots. These args come LAST in the recovery
# mkbootimg recipe, overriding INTERNAL_MKBOOTIMG_VERSION_ARGS (which derives
# 2024-02 from PLATFORM_SECURITY_PATCH). Pinned to the stock level 2023-03.
# (The target-files _BuildBootableImage fallback reorders args so the version
# args would still win there — but BOOTABLE_IMAGES ships the prebuilt image,
# so that path is not used for the payload.)
BOARD_RECOVERY_MKBOOTIMG_ARGS += --os_version 11.0.0 --os_patch_level 2023-03
# Stage the built (padded, v2+dtb) boot image into BOOTABLE_IMAGES/ of the
# target-files zip so add_img_to_target_files/GetBootableImage ships the exact
# tested image in the OTA payload instead of rebuilding it. Also makes the
# payload write the FULL 64 MiB into boot_b (no stale tail left over from the
# previous content of the partition).
BOARD_CUSTOM_BOOTIMG := true
# The Unisoc uboot parses the AVB footer at the end of the boot partition
# BEFORE display init: with no footer it dies in a screen-off watchdog cycle
# (INCIDENT 2B — the zero-padded image, fastboot unreachable). Both proven
# references carry a parseable footer: stock (Unisoc-generated) and PBRP
# (avbtool-generated with the AOSP testkey_rsa4096 — verified: their image's
# footer parses with standard avbtool and boots on this hardware). The
# unlocked bootloader (skip-verify) never verifies the signature, it only
# needs the footer structure. This adds the SAME footer to our boot image —
# content + zero padding + avbtool testkey hash footer = exactly the PBRP
# geometry. Mutually exclusive with BOARD_BOOTIMG_PAD_TO_PARTITION_SIZE (the
# footer step pads itself; a pre-padded image would leave no room) and with
# BOARD_AVB_ENABLE (the real AVB path does its own footer).
BOARD_BOOTIMG_TESTKEY_HASH_FOOTER := true
# Zero-padding WITHOUT a footer is what bricked the screen on test 2 — see
# INCIDENT 2B. Must stay unset while the footer flag above is set.
# BOARD_BOOTIMG_PAD_TO_PARTITION_SIZE := true
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img
BOARD_KERNEL_IMAGE_NAME := Image

# Kernel: SOURCE-BUILT from the official Motorola drop (branch
# android-11-release-RTAS31.68-66-3, commit 261390cd; source kept in
# kernel/motorola/java). Built offline with the validated recipe
# (clang-r383902 + LLD, JOURNEY_BUILD_SCRIPT=yes, CONFIG_LOCALVERSION=-ab66-3):
#   release 4.14.193-ab66-3 (exact stock match; 667/667 module CRCs)
#   Image 19,017,744 B (sha256 79ab75fc..., size == stock; hash differs from
#   the stock binary only by compiler build/ids - clang 11.0.1 vs 11.0.2)
#   built base DTB byte-identical to the shipped prebuilt/kernel/dtb.
# Integrated through the prebuilt slot: LOS kernel.mk's wrapper is fragile for
# this source (Uniosc gate + toolchain path quirks), so the source build is
# driven by the documented standalone recipe instead.
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel/Image
# source tree stays in-tree (kernel/motorola/java) for provenance/rebuilds;
# force the prebuilt slot so kernel.mk doesn't try to drive the fragile wrapper
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_KERNEL_SOURCE := kernel/motorola/java
TARGET_KERNEL_CONFIG := sprd_sharkl5Pro_defconfig
# DTB embedded in the boot image (v1 recovery_dtbo slot, stock layout).
# With BOARD_USES_RECOVERY_AS_BOOT the boot image is built by the recovery
# recipe, which uses BOARD_RECOVERY_MKBOOTIMG_ARGS (not BOARD_MKBOOTIMG_ARGS)
# and packs --recovery_dtbo only when BOARD_INCLUDE_RECOVERY_DTBO is set.
# (--header_version and the load offsets are appended once, above.)
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
# CRITICAL (2026-09-15, bisect-confirmed): the Unisoc uboot requires the boot
# image's dtb blob to be an mkdtimg DT_TABLE (magic d7b7ab1e, 64-byte header +
# entry + FDT, total 155,425). A bare FDT (155,361) crashes it at the
# boot-image stage (resets right after "LOCK FLAG IS: UNLOCK!!!", before
# "skip verify") — the cause of test-2/3/4 bootloops. Stock and PBRP both pack
# the dt_table; the build rule for BOARD_PREBUILT_DTBIMAGE_DIR is a plain
# `cat *.dtb`, so ums512.dtb here IS the packed dt_table blob (byte-identical
# to PBRP's prebuilt/dtb.img — same FDT inside). The raw, provenance-pinned
# FDT remains untouched at prebuilt/kernel/dtb (155,361, d00dfeed).
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/kernel/dtbimg
TARGET_KERNEL_ADDITIONAL_CONFIG :=

# Recovery (recovery-in-boot, A/B)
TARGET_NO_RECOVERY := true
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.ums512_1h10
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_SUPPRESS_SECURE_ERASE := true

# A/B
AB_OTA_UPDATER := true

# Dynamic partitions: super size is stock (5,452,595,200 B = 5,199 MiB).
# Per-partition slots RESIZED from the actual first-build output (the stock
# slots don't fit: our vendor tree is 920 MiB > stock's 781 MiB slot, while
# product shrunk to 410 MiB after dropping the Moto/GMS apps). Sizing gives
# every partition 15-45% headroom over its measured tree:
#   system 1 GiB | system_ext 512 MiB | product 640 MiB | vendor 1,125 MiB
#   group total 3,328 MiB, leaving ~1.8 GiB of super free for future growth.
BOARD_SUPER_PARTITION_SIZE := 5452595200
BOARD_SUPER_PARTITION_GROUPS := motorola_dynamic_partitions
BOARD_SUPER_PARTITION_METADATA_DEVICE := super
BOARD_MOTOROLA_DYNAMIC_PARTITIONS_SIZE := 3489660928
BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext vendor product
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1073741824
BOARD_SYSTEM_EXTIMAGE_PARTITION_SIZE := 536870912
BOARD_VENDORIMAGE_PARTITION_SIZE := 1207959552
BOARD_PRODUCTIMAGE_PARTITION_SIZE := 671088640

# File systems
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_USES_METADATA_PARTITION := true
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE :=
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext

# Flash block size (eMMC)
BOARD_FLASH_BLOCK_SIZE := 4096

# system-as-root (Android 11 convention, no ramdisk-in-system)
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false

# VNDK: stock vendor is API-30 (ro.vndk.version=30). 'current' builds VNDK
# from this platform source and emits ro.vndk.version=$(PLATFORM_VNDK_VERSION)
# = 30; the numeric form 30 requires the prebuilts/vndk/v30 snapshot, which
# the LineageOS 18.1 manifest does not sync.
BOARD_VNDK_VERSION := current

# The merged policy (Lineage platform CILs + stock Unisoc vendor CILs) has
# cross neverallow conflicts (e.g. Lineage llkd ptrace vs Moto neverallow for
# unisoc tool apps). Neverallows are compile-time assertions only - the runtime
# policy (what init compiles) does not check them. This is the AOSP-sanctioned
# bring-up knob (userdebug only; hard-error in user builds).
SELINUX_IGNORE_NEVERALLOWS := true

# Moto G20 (java): the stock vendor SELinux policy objects (CILs + contexts)
# ship verbatim as copy-files from device/motorola/java/sepolicy/vendor. The
# platform-built vendor policy modules are skipped for this board (guards in
# system/sepolicy/Android.mk + Android.bp).
BOARD_MOTO_STOCK_VENDOR_SEPOLICY := true

# Route PRODUCT_PROPERTY_OVERRIDES into vendor/build.prop (stock location of
# the ro.vendor.* property set, incl. ro.vendor.ko.mount.point used by the
# vendor init rc files for every insmod)
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true

# Sepolicy: the stock vendor/ODM policy objects are prebuilt data files
# (see device.mk); no BOARD_VENDOR_SEPOLICY_DIRS inputs (the 18.1 sepolicy
# build cannot consume compiled stock CIL)

# Extra root symlinks matching stock (/odm -> /vendor/odm)
BOARD_ROOT_EXTRA_SYMLINKS += \
    /odm:/vendor/odm

# /system symlinks present on stock (kernel module partitions)
BOARD_SYSTEMIMAGE_EXTRA_SYMLINKS += \
    /mnt/vendor/socko:socko \
    /mnt/vendor/odmko:odmko

# VINTF: the stock manifest ships (DEVICE_MANIFEST_FILE + the 23 stock
# fragment manifests). ENFORCE_VINTF_MANIFEST must stay TRUE here:
# config.mk recomputes PRODUCT_FULL_TREBLE from its requirement list, so a
# false enforcement flips ro.treble.enabled=false, which makes linkerconfig
# generate the LEGACY (flat) linker configuration - the [vendor] section and
# the VNDK-apex namespace vanish, and every vendor binary that links an
# apex-only lib (thermal@2.0, cas@1.1, wifi@1.0, usb@1.0, radio@1.0,
# neuralnetworks@1.3, power/light-V1-ndk_platform, broadcastradio@2.0,
# fingerprint@2.1, libjsoncpp/libxml2 for the camera HAL, ...) dies with
# CANNOT LINK - the iter10 HAL-cascade root cause (test3_capture/iter10).
# If the OTA-time checkvintf step rejects the stock vendor-extension HALs,
# the device manifest/matrix must be corrected - do not waive enforcement
# globally again.
PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := true

# The 23 stock vendor VINTF fragment manifests ship as verbatim copy-files
# (vendor/etc/vintf/manifest/*.xml) exactly as stock lays them out; 18.1
# rejects VINTF metadata in PRODUCT_COPY_FILES to push products onto
# vintf_fragments. Libvintf auto-discovers the fragment directory at runtime,
# so the copies are functionally correct - keep them and relax the check.
BUILD_BROKEN_VINTF_PRODUCT_COPY_FILES := true
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/vintf/manifest.xml
# OTA checkvintf (runs because enforcement is on, see above): the stock
# vendor-extension HALs are unknown to the AOSP framework compatibility
# matrix; this device addendum declares them optional so the check passes.
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := $(DEVICE_PATH)/vintf/framework_compatibility_matrix.xml

# Moto G20 (java): vendor properties missing from the port (diffed against the
# stock vendor/build.prop; see vendor.prop). ro.vendor.product.partitionpath is
# CRITICAL: modem_control builds every modem/NV path from it; without it the
# lookups degrade to not_findl_* and the daemon reboots the device after the
# modem-alive timeout (the iter12 reboot loop).
TARGET_VENDOR_PROP := $(DEVICE_PATH)/vendor.prop

# Device-specific vendor sepolicy additions (.te sources compiled into the
# vendor policy). Currently: the DEBUG boot logger's init file-write access
# (sepolicy/vendor-te/init_bootlog.te — see rootdir/bin/bootlog.sh).
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor-te

# Wi-Fi/BT: vendor wpa_supplicant and the WLAN HAL wrapper ship as blobs.
# Skip the platform-built libwifi-hal (AOSP fallback stub): the stock Unisoc
# wrapper blob must occupy vendor/lib64/libwifi-hal.so.
BOARD_NO_PLATFORM_WIFI_HAL := true
# Do NOT set BOARD_WLAN_DEVICE: it would make libwifi_hal.mk build a platform
# libwifi-hal into vendor/lib64 that collides with the stock blob (and the
# Unisoc wrapper has no source in this tree anyway).

# Audio: vendor audio HAL 6.0 + XML policy ship as blobs
USE_XML_AUDIO_POLICY_CONF := true

# Display
TARGET_USES_HWC2 := true

# Disable QCOM-style additions that do not apply
TARGET_DISABLE_EPHEMERAL := true
