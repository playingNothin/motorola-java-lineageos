#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from the proprietary vendor makefile (extract-utils generated)
$(call inherit-product, vendor/motorola/java/java-vendor.mk)

# Inherit AOSP product configuration
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
# Virtual A/B: the stock super is VAB-provisioned (virtual_ab_device header flag,
# empty _b extents; see docs/project_knowledge/AB_VAB_ANALYSIS.md). Enabling the
# AOSP VAB product config is what makes a payload OTA sideloadable onto the
# factory layout: update_engine_sideload (running with OUR recovery props) takes
# the in-place-snapshot path (CoW on /data) instead of failing the classic
# super/2 fit check. Also sets ro.virtual_ab.enabled=true (system + recovery
# prop.default) and ships e2fsck_ramdisk.
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)

# Inherit LineageOS common product configuration (lineage_* product convention)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Enable updating of A/B virtual partitions
AB_OTA_UPDATER := true

# Dynamic partitions: build META/dynamic_partitions_info.txt into the target-files
# zip so brillo_update_payload emits dynamic_partition_metadata in the OTA payload
# (without this, update_engine treats system/vendor/product/system_ext as static
# partitions and the sideload aborts on missing /dev/block/by-name/system_b etc.).
# GROUP names: update_engine slot-suffixes manifest group names itself
# (motorola_dynamic_partitions -> motorola_dynamic_partitions_b), so the name
# does not need to match the stock group_unisoc_a/b layout.
PRODUCT_USE_DYNAMIC_PARTITIONS := true

DEVICE_PATH := device/motorola/java

# Force unauthenticated ADB on userdebug (recovery included): Lineage's
# vendor/lineage/config/common.mk defaults to ro.adb.secure=1 for non-eng
# builds, which contradicts the documented recovery bring-up (unauthenticated
# recovery ADB). NOTE: in the R-era product walk the inherited makefiles are
# parsed BEFORE this file, so common.mk's `ifdef WITH_ADB_INSECURE` cannot see
# an assignment made here; the effective override is the property re-assert in
# device.mk (PRODUCT_SYSTEM_DEFAULT_PROPERTIES += ro.adb.secure=0). This knob
# stays as the documented intent.
WITH_ADB_INSECURE := true

# Device configuration
$(call inherit-product, $(DEVICE_PATH)/device.mk)

# Shipping API level (stock launches with 30)
PRODUCT_SHIPPING_API_LEVEL := 30

# Moto G20 (java): Unisoc SDK boot-classpath jars (stock boot-*.vdex proves
# they were on the stock boot classpath). The IMS cluster apps import classes
# from these; without them com.android.phone dies with NoClassDefFoundError
# (UtilLog) and the IMS stack cannot bind its SDK classes.
PRODUCT_BOOT_JARS += \
    radio_interactor_common \
    com.unisoc.sdk.common \
    uniframework \
    unisoc_ims_common

# Device identifiers
PRODUCT_DEVICE := java
PRODUCT_NAME := lineage_java
PRODUCT_BRAND := motorola
PRODUCT_MODEL := moto g(20)
PRODUCT_MANUFACTURER := motorola

PRODUCT_GMS_CLIENTID_BASE := android-motorola

PRODUCT_BUILD_PROP_OVERRIDES += \
    TARGET_DEVICE=java \
    PRODUCT_NAME=java \
    PRIVATE_BUILD_DESC="java_retail-user 11 RTAS31.68-66-3 66-3 release-keys"

BUILD_FINGERPRINT := "motorola/java_retail/java:11/RTAS31.68-66-3/66-3:user/release-keys"
