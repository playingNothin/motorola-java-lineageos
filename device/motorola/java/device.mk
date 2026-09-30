#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/motorola/java

# Unauthenticated ADB (lineage_java.mk sets WITH_ADB_INSECURE, but the R-era
# product walk parses vendor/lineage/config/common.mk BEFORE this file, so its
# `ifdef WITH_ADB_INSECURE` branch is already evaluated by then and common.mk's
# ro.adb.secure=1 lands in prop.default. Re-assert the same property here: the
# value is appended AFTER common.mk's and the last line wins at load time.
# Without this, adbd (daemon/main.cpp) computes
#   auth_required = ro.adb.secure (=1) && ro.adb.secure.recovery (default true)
# for a userdebug recovery, i.e. recovery ADB would sit "unauthorized" forever
# on freshly-flashed userdata (no stored adb keys) and the recovery diagnosis
# path of the flash plan would be unusable.
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += ro.adb.secure=0

# SELinux runtime policy: init (selinux.cpp GetVendorMappingVersion) REQUIRES
# /vendor/etc/selinux/plat_sepolicy_vers.txt before it can compile the runtime
# policy — missing file = LoadSplitPolicy fails = LOG(FATAL) with
# init_fatal_panic=true = instant panic-shutdown on the first normal boot.
# Nothing in the product config referenced the module (it exists in
# system/sepolicy/Android.mk but was never in any PRODUCT_PACKAGES), so the
# built vendor image shipped without it. Host-replicated secilc compile with
# the image's exact CILs passes (714 KB binary policy), so this file was the
# only blocker for the SELinux stage.
PRODUCT_PACKAGES += \
    plat_sepolicy_vers.txt

# DEBUG: init wrapper — replaces the recovery ramdisk /init (a symlink) with
# a script that mounts /metadata and streams the kernel console to
# /metadata/bootlog/console.log before execing the real init. Captures the
# ENTIRE boot console (first-stage, switch_root, SELinux, services) on a
# power-safe partition. Remove after bring-up.
BOARD_RECOVERY_IMAGE_PREPARE += rm -f $(TARGET_RECOVERY_ROOT_OUT)/init ; cp $(DEVICE_PATH)/rootdir/etc/init.wrapper $(TARGET_RECOVERY_ROOT_OUT)/init ; chmod 755 $(TARGET_RECOVERY_ROOT_OUT)/init

# A/B
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    system \
    system_ext \
    vendor \
    product

# Boot image / fstab (first stage mount reads fstab.$(ro.hardware);
# androidboot.hardware=ums512_1h10 comes from the bootloader cmdline)
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/fstab.ums512_1h10:$(TARGET_COPY_OUT_RAMDISK)/first_stage_ramdisk/fstab.ums512_1h10 \
    $(DEVICE_PATH)/rootdir/etc/fstab.ums512_1h10:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.ums512_1h10 \
    $(DEVICE_PATH)/rootdir/etc/fstab.p352:$(TARGET_COPY_OUT_RAMDISK)/first_stage_ramdisk/fstab.p352 \
    $(DEVICE_PATH)/rootdir/etc/fstab.p352:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.p352 \
    $(DEVICE_PATH)/rootdir/etc/fstab.ums512_1h10:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.ums512_1h10

# module fallback / canary system
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/bin/module_fallback.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/module_fallback.sh \
    $(DEVICE_PATH)/rootdir/etc/init.java-fallback.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/init.java-fallback.rc

# Radio module builds the canary stages onto the socko partition.
# The vendor HALs load sprdwl_ng / sprdbt_tty themselves from socko via
# finit_module; recon = reconstructed drivers (current test build),
# stock = known-good baseline from the stock socko partition.
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/radio_modules/recon/sprdwl_ng.ko:$(TARGET_COPY_OUT_SYSTEM)/lib/modules/recon/sprdwl_ng.ko \
    $(DEVICE_PATH)/radio_modules/recon/sprdbt_tty.ko:$(TARGET_COPY_OUT_SYSTEM)/lib/modules/recon/sprdbt_tty.ko \
    $(DEVICE_PATH)/radio_modules/stock/sprdwl_ng.ko:$(TARGET_COPY_OUT_SYSTEM)/lib/modules/stock/sprdwl_ng.ko \
    $(DEVICE_PATH)/radio_modules/stock/sprdbt_tty.ko:$(TARGET_COPY_OUT_SYSTEM)/lib/modules/stock/sprdbt_tty.ko

# GPU: stock mali_gondul.ko lives on the socko partition (not in the
# kernel tree); load it before surfaceflinger starts
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/init.java-graphics.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/init.java-graphics.rc

# AVB GSI keys referenced by the fstab system entry (match stock ramdisk)
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/avb/q-gsi.avbpubkey:$(TARGET_COPY_OUT_RAMDISK)/first_stage_ramdisk/avb/q-gsi.avbpubkey \
    $(DEVICE_PATH)/rootdir/avb/r-gsi.avbpubkey:$(TARGET_COPY_OUT_RAMDISK)/first_stage_ramdisk/avb/r-gsi.avbpubkey \
    $(DEVICE_PATH)/rootdir/avb/s-gsi.avbpubkey:$(TARGET_COPY_OUT_RAMDISK)/first_stage_ramdisk/avb/s-gsi.avbpubkey

# DEBUG: HANGDIAG — opt-in boot diagnostic instrument. Kernel auto-arms
# only when the developer sets the HANGDIAG_ON flag in misc (offset 65536)
# from Recovery; bootlog_diag captures the console log for that session
# only; hangdiag_disarm tears everything down after sys.boot_completed=1.
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/bootlog.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/bootlog.rc \
    $(DEVICE_PATH)/rootdir/etc/bootlog.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/bootlog.sh \
    $(DEVICE_PATH)/rootdir/etc/hangdiag_disarm.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/hangdiag_disarm.sh \
    $(DEVICE_PATH)/rootdir/etc/init.java-late.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/init.java-late.rc

# VINTF: the root vendor manifest is installed via DEVICE_MANIFEST_FILE
# (BoardConfig.mk) - PRODUCT_COPY_FILES to $(TARGET_COPY_OUT_VENDOR)/etc/vintf/
# is rejected by the 18.1 build. The ODM manifest fragment (stock
# vendor/odm/etc/vintf/manifest_2.xml) is reached at runtime through the
# /odm -> /vendor/odm symlink, so it installs into the vendor image.
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/vintf/odm_manifest_2.xml:$(TARGET_COPY_OUT_VENDOR)/odm/etc/vintf/manifest_2.xml

# SELinux: stock vendor/ODM policy objects ship as prebuilt data files at the
# exact paths init reads. The 18.1 sepolicy build only consumes .te/named
# context sources from BOARD_VENDOR_SEPOLICY_DIRS, so compiled stock CIL cannot
# be fed as input; instead the build's own precompiled_sepolicy is disabled
# (init then compiles plat(Lineage) + stock vendor/odm CIL at boot) and the
# stock objects overwrite the build-generated ones at the same paths.
PRODUCT_PRECOMPILED_SEPOLICY := false
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/sepolicy/vendor/odm_sepolicy.cil:$(TARGET_COPY_OUT_VENDOR)/odm/etc/selinux/odm_sepolicy.cil \
    $(DEVICE_PATH)/sepolicy/vendor/vndservice_contexts:$(TARGET_COPY_OUT_VENDOR)/etc/selinux/vndservice_contexts \
    $(DEVICE_PATH)/sepolicy/vendor/vendor_seapp_contexts:$(TARGET_COPY_OUT_VENDOR)/etc/selinux/vendor_seapp_contexts \
    $(DEVICE_PATH)/sepolicy/vendor/vendor_mac_permissions.xml:$(TARGET_COPY_OUT_VENDOR)/etc/selinux/vendor_mac_permissions.xml

# Recovery (recovery-as-boot): LineageOS 18.1 recovery execs
# /system/bin/update_engine_sideload to apply A/B payload OTAs
# (bootable/recovery/install/install.cpp). Nothing in the 18.1 tree adds this
# module for A/B devices; the module carries recovery: true, so this
# PRODUCT_PACKAGES entry places it in the recovery ramdisk.
PRODUCT_PACKAGES += \
    update_engine_sideload

# fastbootd (userspace fastboot in recovery): the stock recovery ramdisk ships
# system/bin/fastbootd plus android.hardware.boot@1.0-impl-1.1.so (AOSP
# libboot_control over misc - matches the stock uboot A/B algorithm) and
# android.hardware.fastboot@1.0-impl.so. fastbootd handles dynamic partitions
# itself via liblp (system/core/fastboot), so no vendor bootctrl blob is needed.
# HIDL passthrough lookup loads any android.hardware.*@ver-impl*.so from
# system/lib64/hw, so the AOSP -mock module name works as-is.
#   - fastbootd              system/core/fastboot (recovery: true)
#   - boot@1.1-impl          stem android.hardware.boot@1.0-impl-1.1; the .recovery
#                            suffix is REQUIRED to install the recovery variant
#                            (same convention as base_vendor.mk's health impl);
#                            the plain name installs the vendor variant
#   - fastboot@1.0-impl-mock partition vars (recovery); health impl comes from
#                            base_vendor.mk (android.hardware.health@2.0-impl-default.recovery)
PRODUCT_PACKAGES += \
    fastbootd \
    android.hardware.boot@1.1-impl \
    android.hardware.boot@1.1-impl.recovery \
    android.hardware.fastboot@1.0-impl-mock

# Recovery ADB: the stock Unisoc kernel has no legacy android_usb f_ffs node,
# so recovery's sys.usb.configfs=0 default cannot attach adbd on this device.
# The configfs gadget path is proven working (stock normal boot runs
# sys.usb.configfs=1). This device rc is imported first by recovery's init.rc
# and selects the configfs branch before "on fs" fires.
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/rootdir/etc/init.recovery.ums512_1h10.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.ums512_1h10.rc

# Recovery touch (see rootdir/etc/init.recovery.ums512_1h10.rc): the touch
# modules and firmware live in the device tree under recovery/root/vendor/
# (TWRP model) — $(TARGET_DEVICE_DIR)/recovery/root is packed into the
# recovery ramdisk automatically, so no copy-files entries are needed here.

# Public libraries list provided by the platform build (vendor copy references it)
# public.libraries-sprd.txt ships via java-vendor.mk as a system copy file.

# Screen
TARGET_SCREEN_HEIGHT := 1600
TARGET_SCREEN_WIDTH := 720
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := 280dpi

# Props from stock vendor/build.prop (partition-relative properties).
# PRODUCT_VENDOR_PROPERTIES does not exist in Android 11 / LOS 18.1;
# PRODUCT_PROPERTY_OVERRIDES + BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED=true
# routes these into vendor/build.prop (same location as stock).
PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.board=p352 \
    ro.vendor.ko.mount.point=/mnt/vendor \
    ro.vendor.camera.dualcamera_cali_enable=1 \
    ro.vendor.camera.dualcamera_cali_time=3 \
    ro.vendor.mmi.camera.sensor.cct=ams_tcs3430 \
    ro.vendor.validationtools.fmdisable=1 \
    ro.vendor.audio_tunning.nr=1 \
    ro.vendor.display.sr=true \
    ro.vendor.modem.dev=/proc/cptl/ \
    ro.vendor.modem.tty=/dev/stty_lte \
    ro.vendor.modem.eth=seth_lte \
    ro.vendor.modem.snd=1 \
    ro.vendor.radio.modemtype=l \
    ro.vendor.modem.diag=/dev/sdiag_lte \
    ro.vendor.modem.log=/dev/slog_lte \
    ro.vendor.modem.loop=/dev/spipe_lte0 \
    ro.vendor.modem.nv=/dev/spipe_lte1 \
    ro.vendor.modem.assert=/dev/spipe_lte2 \
    ro.vendor.modem.fixnv_size=0x100000 \
    ro.vendor.modem.runnv_size=0x120000 \
    ro.vendor.modem.gnss.diag=/dev/slog_gnss \
    ro.vendor.ag.log=/dev/audio_dsp_log \
    ro.vendor.ag.pcm=/dev/audio_dsp_pcm \
    ro.vendor.ag.mem=/dev/audio_dsp_mem \
    ro.vendor.gnsschip=marlin3lite \
    ro.vendor.wcn.gpschip=marlin3lite \
    vendor.audio.param.version=audio_params_20210622_POLQA

# Props from stock vendor/default.prop (vendor default properties)
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.vendor.gpu.boost=0 \
    camera.disable_zsl_mode=1 \
    ro.oem_unlock_supported=1 \
    ro.logd.size.stats=64K \
    log.tag.stats_log=I \
    ro.surface_flinger.vsync_event_phase_offset_ns=1000000 \
    ro.surface_flinger.vsync_sf_event_phase_offset_ns=1000000 \
    ro.surface_flinger.use_context_priority=true \
    ro.surface_flinger.has_wide_color_display=false \
    ro.surface_flinger.has_HDR_display=false \
    ro.surface_flinger.present_time_offset_from_vsync_ns=0 \
    ro.surface_flinger.force_hwc_copy_for_virtual_displays=false \
    ro.surface_flinger.max_virtual_display_dimension=0 \
    ro.surface_flinger.running_without_sync_framework=false \
    ro.surface_flinger.use_vr_flinger=false

# Props from stock ramdisk prop.default (runtime behavior knobs)
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    persist.vendor.sys.modem.diag=disable \
    persist.vendor.modem.log_dest=0 \
    persist.vendor.wcn.log_dest=0 \
    persist.vendor.sys.modemreset=1 \
    persist.vendor.sys.modem.save_dump=0 \
    persist.vendor.modem.nvp=l_ \
    persist.vendor.modem.l.enable=1 \
    persist.vendor.sys.wcnreset=1 \
    persist.vendor.sys.wcnstate=0 \
    persist.vendor.cam.res.multi.camera=RES_MULTI_12M \
    persist.vendor.cam.res.multi.camera.fullsize=1 \
    persist.vendor.cam.multi.camera.enable=1 \
    camera.disable_zsl_mode=1

# Media / codec related (stock behavior)
PRODUCT_PROPERTY_OVERRIDES += \
    media.stagefright.thumbnail.prefer_hw_codecs=true

# Health charging: stock uses /vendor/bin/charge (offline charge) - no changes needed

# fstab.ums512_1h10 / fstab.p352 are installed as PRODUCT_COPY_FILES above
# (they are not build modules). Filesystem tools for f2fs userdata:
PRODUCT_PACKAGES += \
    make_f2fs \
    fsck.f2fs

# Recovery
TARGET_USES_MKE2FS := true

# Vendor blobs the extract-files pass missed (keymaster/trusty stack, audio,
# DRM, NFC, HWComposer adapters). Gap analysis vs the stock vendor dump.
PRODUCT_COPY_FILES += $(foreach f,$(wildcard $(DEVICE_PATH)/vendor-extra/lib64/*.so),$(f):$(TARGET_COPY_OUT_VENDOR)/lib64/$(notdir $(f)))
PRODUCT_COPY_FILES += $(foreach f,$(wildcard $(DEVICE_PATH)/vendor-extra/lib/*.so),$(f):$(TARGET_COPY_OUT_VENDOR)/lib/$(notdir $(f)))

# Keymaster/TEE stack: AOSP-source modules that were built all along but
# never installed (the B9 vendor-blob culling removed their blob versions
# due to collisions with these same AOSP modules). Providing them via
# PRODUCT_PACKAGES installs the source-built variants into vendor.
PRODUCT_PACKAGES += \
    libtrusty \
    libalsautils \
    libkeymaster41.vendor \
    libkeymaster4.vendor \
    libkeymaster4_1support.vendor \
    libkeymaster4support.vendor \
    libkeymaster_messages.vendor \
    libkeymaster_portable.vendor \
    libpuresoftkeymasterdevice.vendor \
    libsoft_attestation_cert.vendor \
    libkeystore-engine-wifi-hidl.vendor \
    libkeystore-wifi-hidl.vendor

# SPRD TEE blobs (vendor repo prebuilt modules, same culling issue)
PRODUCT_PACKAGES += \
    libkernelbootcp.trusty \
    libteeproduction \
    libhidltransport.vendor \
    libhwbinder.vendor

# iter9 batch (2026-09-22): 32 more vendor files that stock ships but the
# build never installed (leading '-' in proprietary-files.txt = "platform
# provides it", or B9 culling) — mapped via readelf to the HAL deaths of
# the iter9 boot. vendor_available modules need the .vendor suffix;
# vendor:/proprietary:true modules take the plain name.
PRODUCT_PACKAGES += \
    libdrm.vendor \
    libchrome.vendor \
    libaudiofoundation.vendor \
    android.hardware.graphics.composer@2.1-resources.vendor \
    android.hardware.sensors@1.0-impl \
    android.hardware.audio.common@5.0-util.vendor \
    android.hardware.audio.common@6.0-util.vendor \
    libsensorndkbridge \
    libhwc2on1adapter \
    libhwc2onfbadapter \
    android.hardware.health@2.1-impl \
    android.hardware.memtrack@1.0-impl \
    camera.device@1.0-impl \
    libcamera2ndk_vendor \
    libnbaio_mono \
    libtinyxml \
    libtinycompress \
    libkeystore-wifi-hidl \
    libkeystore-engine-wifi-hidl \
    android.hardware.audio@6.0-impl \
    android.hardware.audio.effect@6.0-impl \
    android.hardware.audio.common-util \
    audio.usb.default \
    audio.r_submix.default

# Moto G20 (java): Unisoc SDK boot-classpath jars (see lineage_java.mk
# PRODUCT_BOOT_JARS + the dex_import modules in Android.bp). These install the
# jars to /system/framework that the BOOTCLASSPATH references; the IMS cluster
# apps import their classes (UtilLog, RadioInteractor, UniTelephonyManager).
PRODUCT_PACKAGES += \
    radio_interactor_common \
    com.unisoc.sdk.common \
    uniframework \
    unisoc_ims_common
