#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Motorola Moto G20 (XT2128-1), codename java.
# Extracts proprietary blobs from a stock RTAS31.68-66-3 device (ADB, default)
# or from a filesystem dump directory / OTA zip.
#
# Usage:
#   ./extract-files.sh                # extract from a device connected via ADB
#   ./extract-files.sh <dump_dir>     # extract from a filesystem dump
#                                     # (dump/system dump/vendor dump/system_ext
#                                     #  dump/product)
#   ./extract-files.sh <ota.zip>      # extract from an OTA zip (A/B OTA not
#                                     # supported by extract-utils)
#
# Options:
#   -n, --no-cleanup    do not clean the vendor directory before extraction
#   -k, --kang          print blob hashes for pinning (see proprietary-files.txt)
#   -s, --section NAME  extract only the section <name> of proprietary-files.txt
#

set -e

DEVICE=java;
VENDOR=motorola;

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh" "$@"
