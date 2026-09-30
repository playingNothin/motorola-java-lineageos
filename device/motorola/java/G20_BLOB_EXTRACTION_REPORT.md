# Moto G20 (java) — Proprietary Blob Extraction System — Final Report

**Device:** Motorola Moto G20 XT2128-1 (`java`, board p352, Unisoc UMS512/Tiger T700, sharkl5pro)
**Stock firmware:** RTAS31.68-66-3 (Android 11, A/B, dynamic partitions, slot `_a` at test time)
**Target:** LineageOS 18.1
**Extraction infrastructure:** official LineageOS 18.1 shell extract-utils
(`tools/extract-utils/extract_utils.sh` @ lineage-18.1, HEAD `18705c3`; `prebuilts/extract-tools` @ lineage-18.1)

---

## 1. Files created

In the LineageOS tree (WSL: `~/lineage/device/motorola/java/`, mirrored at
`G:\Arquivos Moto G20\_analysis\build\`):

| File | Purpose |
|---|---|
| `extract-files.sh` | Extraction driver per the 18.1 single-device template. `DEVICE=java`, `VENDOR=motorola`, loads `${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh`, **defaults to ADB** when no source is given, supports `-n/--no-cleanup`, `-k/--kang`, `-s/--section`, dump-directory and OTA-zip sources, calls `extract`, then `setup-makefiles.sh`. |
| `setup-makefiles.sh` | Per the 18.1 template: `setup_vendor` + `write_headers` + `write_makefiles proprietary-files.txt` + `write_footers`; generates `vendor/motorola/java/{java-vendor.mk, Android.bp, Android.mk, BoardConfigVendor.mk}`. |
| `proprietary-files.txt` | **1832 evidence-based entries** (syntax: `[src:]dst[;args][|sha1]`, `-` = prebuilt module, plain = PRODUCT_COPY_FILES), organized in labeled sections usable with `--section`. |
| `G20_BLOB_EXTRACTION_REPORT.md` | This report (kept with the device tree). |

Generated vendor repo (WSL `~/lineage/vendor/motorola/java`, symlinked to
`G:\Arquivos Moto G20\_analysis\build\vendor_repo\motorola\java` to keep heavy data off the full C: drive):

| File | Content |
|---|---|
| `java-vendor.mk` | 696 `PRODUCT_COPY_FILES` + `PRODUCT_PACKAGES` (713 modules) + `PRODUCT_SOONG_NAMESPACES` |
| `Android.bp` | 713 modules: 559 `cc_prebuilt_library_shared`, 126 `cc_prebuilt_binary`, 9 `sh_binary`, 18 `android_app_import`, 1 `dex_import` |
| `Android.mk`, `BoardConfigVendor.mk` | Template headers + guard (no legacy makefile modules needed) |
| `proprietary/` | **1832 extracted blobs** |

Supporting artifacts (Windows side, `_analysis/`):

| Artifact | Content |
|---|---|
| `dump/{system,vendor,system_ext,product}` | Full partition trees materialized from `super.img` (LP v2 parser; `imgs/super_raw.img` + per-partition raw images) |
| `build/blob_sha1.txt` | SHA-1 of all 1832 extracted blobs |
| `build/java_extract_dump.log`, `g20tmp/java_extract_adb2.log` | Raw extraction logs (dump mode, adb mode) |
| `g20tmp/adb_failed.txt`, `g20tmp/adb_extracted.txt` | Exact adb-mode failed/extracted file lists |
| `build/blob_classification.json`, `build/final_closure.json`, `build/dt_needed_closure.json`, `dump/dump_manifest.json` | Per-entry partition/arch/kind classification and DT_NEEDED closure data |
| `tools/extract_dump.py`, `tools/simg2raw.py`, `tools/build_prop_files.py`, `tools/final_closure.py`, `tools/compare_fw_runtime.py` | Reproducible toolchain used to build the dump and the blob list |

## 2. proprietary-files.txt — totals

**Total entries: 1832** (1136 prebuilt packages `-`, 696 copy-files) — 0 duplicates, 0 syntax errors, all parse through the 18.1 helper.

**By originating partition:**

| Partition | Entries | Notes |
|---|---|---|
| vendor | 1646 | bin(80)+bin/hw(38), lib(492), lib64(410), etc(475), firmware/logo/media/usr/cfg(149), app(2), ueventd.rc(1) — incl. `vendor/odm/etc/vintf/manifest_2.xml` as odm copy |
| system_ext | 175 | lib64(48)+lib(23), etc(70), apps(8), priv-apps(8), bin(17), framework jar(1) |
| system | 10 | 5 sprd client libs × lib+lib64, `public.libraries-sprd.txt` |
| odm | 1 | `vendor/odm/etc/vintf/manifest_2.xml` (stock keeps odm inside vendor; `/odm` is a runtime symlink) |

**By architecture (ELF header scan of entries):**

| Class | Count |
|---|---|
| 64-bit ELF | 555 |
| 32-bit ELF | 541 |
| non-ELF (XML/INI/conf/firmware/rgba/bin/… ) | 732 |
| n/a (dirs-agnostic entries: apk/jar counted by content) | 4 |

Generated modules: **423 multilib (lib+lib64 pairs, `compile_multilib: "both"`)**, 96 32-bit-only, 40 64-bit-only — 423+96+40 = 559 shared-lib modules; 1136 package entries − 423 merged pairs = **713 PRODUCT_PACKAGES**, verified 1:1 against `Android.bp` module names.

**32-bit support preserved:** the stock Unisoc camera provider, audio service, CAS, Widevine, OMX, engpc/factorytest chain and all their libraries are 32-bit (541 32-bit ELF entries, 96 32-only modules). The device tree must enable `TARGET_2ND_ARCH`/32-bit binder (standard for zygote64_32).

**Required vs optional:** every included entry is part of the stock vendor/system_ext runtime that boots the device (HAL services + their DT_NEEDED closure, vendor configs consumed by init/HALs, IMS/telephony stack, camera/audio/gfx stacks). Deliberately **excluded** (evidence in §7): Google GMS/product apps, Motorola consumer apps (MotoHelp/MotoLauncher/MotoOta/MotoCare/facebook/LenovoID/…), factory-only apps (CQATestNoIcon, ApeCamFacCalibration, ApeFTM_R_USER, DemoMode), stock apps LineageOS replaces (Settings, SystemUI, TeleService, Stk, SprdContacts/CalendarProvider, StorageManager, WallpaperCropper, SetupWizard, …), NFC stack (no NFC hardware), vendor/overlay RROs (target stock system components), kernel modules (`vendor/lib/modules/*.ko`, `socko.img`) → belong to the kernel/module mechanism, build-regenerated files (build.prop, precompiled_sepolicy, vintf manifest/compat matrix, wpa_supplicant.conf, toybox symlinks, fs_config artifacts, NOTICE, adb.iso).

## 3. Firmware vs runtime comparison (RTAS31.68-66-3 super.img ↔ live device)

Method: full file tables from the extracted partition images (`files_*_a.txt` inventories, 1721 vendor files + 197 symlinks, 286 system_ext, 496 product, 26 socko) compared against runtime listings from the live device (`find /vendor /system_ext /product /system /mnt/vendor/socko` over ADB).

- **vendor:** 1721/1721 firmware files present at runtime (0 runtime-only, 0 firmware-only). The 75-path initial discrepancy was a `find`-stat artifact (SELinux denies the shell domain `getattr` on `/vendor/bin`; the files are there and `ls` shows them).
- **system_ext:** 286/286 present at runtime; app `lib/arm64/*.so` entries are symlinks into `system_ext/lib64` in both firmware and runtime.
- **product:** 496/496 identical.
- **socko:** 26 kernel modules present in firmware; runtime `find` cannot enumerate `/mnt/vendor/socko` (SELinux) but the modules are insmod'd from there by init (verified by the prior module/CRC work — 26 modules, 667/667 CRC matches).
- **odmko:** empty (lost+found) in both firmware and runtime.
- **Renamed/repackaged:** none found.
- **Content identity:** SHA-1 spot checks of device-pulled files vs dump-extracted files are byte-identical (`libsprdssense.so`, `urild`, `vdsp_firmware.bin`) — the dump is a faithful source.
- **Symlinks:** `/system/{vendor,product,system_ext,odmko,socko}` → partition mounts at runtime; `/odm/*` → `/vendor/odm/*`; vendor-internal lib symlink chains (`libOpenCL.so*`) ship as regular extracted files (identical to what adb pull/cp produce).

**Firmware-only / runtime-only files: none** in the blob-relevant partitions. Files needed by runtime but absent from the firmware tree: none.

**Missing firmware (not blobs, flagged for bring-up):** `wcnmodem` and `pm_sys` partition images are absent from the local PAC package (both are optional-in-pack partitions; the runtime has them flashed). They are partition images (modem/WCN/sensorhub firmware), not userspace blobs, and are out of scope for proprietary-files.txt — but WiFi/BT/sensorhub bring-up needs them preserved on the device or re-obtained.

## 4. Extraction tests (real runs)

### 4a. ADB mode (default source) — `./extract-files.sh` on the stock device

- 1832 attempted → **689 extracted, 1143 failed** (exact lists in `g20tmp/adb_failed.txt`, `adb_extracted.txt`).
- **Every failure explained:**
  - **1133 files** — SELinux denies the untrusted `shell` domain read/getattr on `vendor_file`-family and `system_ext` exec labels: all `vendor/bin`, `vendor/lib(64)` except the 50 "vendor public" libs (GPU/OpenCL/gralloc/vulkan/mapper/renderscript/camera-public set, `libhidltransport`, `libhwbinder`, `libdrm`), `vendor/logo`, `vendor/firmware`, `vendor/usr`, `vendor/media`, `vendor/app`, `vendor/cfg`, `vendor/ueventd.rc`, and 11 of 17 `system_ext/bin` daemons. Verified empirically (`adb pull` → `Permission denied` on stat) — this is stock Motorola policy; a user build cannot be rooted (`adb root` blocked). **This is why the firmware dump is required for vendor blobs on this device.**
  - **10 files** (9 `system/lib*`, 1 `system/etc/public.libraries-sprd.txt`) — the 18.1 helper always pulls `/system/<path>`; this device is system-as-root, so system content lives at runtime `/system/...` but never `/system/system/...`. These entries extract correctly from a dump (`$SRC/system/<path>` fallback). Known extract-utils 18.1 limitation for system-as-root devices, not a list error.
- Successful adb subset: all 474 vendor/etc configs, all system_ext libs/apps/etc (164), 50 vendor public libs, odm vintf manifest.
- Reproducible workaround for the adb bridge in WSL (no device modification): Windows adb server listening on all interfaces (`adb -a -P 5037 nodaemon server`) + `ADB_SERVER_SOCKET=tcp:<win-host>:5037`.

### 4b. Dump mode — `./extract-files.sh <dump>`

- Source: full partition trees materialized from the RTAS31.68-66-3 `super.img` (sparse→raw, LP v2 extents, ext4 walk; system-as-root `/system` subtree mapped to `dump/system`).
- Result: **1832 / 1832 extracted — 0 failures, 0 missing, 0 extra** (verified by path diff of entries vs tree).
- **Dump path must not contain spaces**: the 18.1 helper invokes `get_file` with unquoted arguments; a spaced `SRC` breaks argument splitting. Use a space-free path (this test used `~/g20dump` → symlink to the dump). Also `TMPDIR` must be space-free when using `--section` (unquoted `$LIST` redirect in the helper).
- Deodex: the `oat2dex`/vdexExtractor pipeline is wired and working (ARCHES detection found arm64+arm boot.oat in the dump); **it was not needed** — all 18 included APKs carry native `classes.dex` (verified 18/18 in the firmware). Environment note: this WSL lacked `zip`/`unzip`/`java`; `zip` was fetched non-root for the pipeline; a normal LineageOS build host already has it.

### 4c. `--section` mode

- `./extract-files.sh -s "system_ext libraries" <dump>` → 71 entries attempted, 0 failures, vendor tree untouched (as designed, `-s` implies no-cleanup).

## 5. Blob fixups

**None.** `blob_fixup()` is intentionally absent from `extract-files.sh`. Reason: LineageOS 18.1 targets the same API/VNDK level (Android 11 / VNDK 30) as stock RTAS31.68-66-3, no evidence of any dependency mismatch was found (DT_NEEDED closure fully resolves, §6), and no speculative patchelf/sed rules were added. If a future platform bump (e.g. 19+) requires fixups, add them there with per-blob evidence and a second `|fixup_sha1` pin.

## 6. Dependency closure validation (the "no invented, no missing" proof)

DT_NEEDED parsed from **142 ELF binaries** (all 118 `vendor/bin/**` incl. `hw/` + `power/**`, 17 `system_ext/bin`, scripts/json excluded) in the final extracted tree:

- **120 unique DT_NEEDED dependencies**
- **33 resolved from extracted blobs** (e.g. `librilcore.so`, `libatci.so`, `libcamera.ums512.so`… via the 32-bit services, `libcheckkeybox.so` via `npidevice/`, `libvdspservice.so` via system_ext)
- **87 resolved from the platform** (AOSP HIDL interface libs `android.hardware.*`, `android.hidl.*`, `android.system.net.netd@1.x`, AIDL NDK libs, VNDK v30 core libs `libhidlbase/libutils/libbinder/…`, bionic `libc/libm/libdl`)
- **0 unresolved**

Full data: `build/final_closure.json` (per-binary), `build/dt_needed_closure.json` (dump-side, 270 binaries incl. toybox copies).

## 7. Module / partition correlation (what is NOT in the blob list, on purpose)

- **26 socko kernel modules** (`socko.img`, runtime `/mnt/vendor/socko`): camera (sprd_camera/cpp/fd/mmdvfs), Mali (`mali_gondul`), WCN (`sprdwl_ng`, `sprdbt_tty`, `sprd_fm`), VDSP (`sprd_vdsp`, `vdsp_sipc`, `vdsp_spipe`), sensors (`sprd_sensor`, `tcs3430`, `stmvl53l0`), touch (NVT/focaltech/oreo_ili9882n/ssd20xx/synaptics), fingerprint (chipone/fpc/microarray), flash (sprd_flash_drv + 3 ICs). **Kernel `.ko` are not userspace blobs** — they are covered by the kernel deliverable (26/26 modules, 667/667 CRC matches, vermagic and DTB byte-identity already established). `vendor/lib/modules/*.ko` (incfs, kheaders, tracing) likewise excluded → ship via `BOARD_VENDOR_KERNEL_MODULES`.
- **Partition firmware images** (flashed, not vendored): `l_modem`, `l_ldsp/l_gdsp/l_agdsp/l_cdsp`, `gnssmodem`, `EXEC_KERNEL_IMAGE`, `sharkl5pro_cm4.bin`, DSP bins, `tos/sml/teecfg/u-boot/fdl*` — preserved as partitions; Trusty userspace side (keymaster/gatekeeper/rpmbserver/sprdstorageproxyd/tsupplicant + TAs `fpctzapp.elf`/`fpsensor.elf` in `vendor/firmware`) **is** in the blob list.
- **NFC**: `android.hardware.nfc@1.2-service` + `nfc_nci_nxp/ese_spi_nxp/ese_client/hal_libnfc/vendor.nxp.*.so` + `com.nxp.ls.jar` excluded — evidence: no `android.hardware.nfc` feature on the device, the service rc is gated `property:ro.boot.product.hardware.sku=2` and `disabled`, and no NFC entry exists in any vendor VINTF manifest.
- **product partition**: GMS apps + Motorola retail apps — excluded entirely (documented above).
- **/odm**: no separate odm partition (odmko empty); odm content lives in `vendor/odm` — the one odm file (vintf fragment) ships as `vendor/odm/...`; the device tree must provide the `/odm → /vendor/odm` rootfs symlink exactly like stock.

## 8. Exact commands used

```bash
# firmware → dump (Windows python, _analysis/tools/)
python simg2raw.py                # super.img sparse → raw
python extract_dump.py            # LP v2 parse + ext4 walk → dump/{system,vendor,system_ext,product}
python build_prop_files.py        # inventories + rules → proprietary-files.txt (1832)

# device tree
cp _analysis/build/{extract-files.sh,setup-makefiles.sh,proprietary-files.txt} \
   ~/lineage/device/motorola/java/   # + strip CR, chmod +x
bash -n extract-files.sh && bash -n setup-makefiles.sh

# adb bridge (WSL → Windows adb server; device unmodified)
adb kill-server && adb -a -P 5037 nodaemon server      # Windows side
export ADB_SERVER_SOCKET=tcp:172.26.64.1:5037          # WSL side

# tests
cd ~/lineage/device/motorola/java
./extract-files.sh                                    # adb default (689/1832; SELinux+system-as-root limits)
./extract-files.sh ~/g20dump                          # dump mode (1832/1832)
./extract-files.sh -n                                 # adb capture run (no cleanup)
./extract-files.sh -s "system_ext libraries" ~/g20dump
./setup-makefiles.sh                                  # makefile regeneration check

# validation
python final_closure.py                               # DT_NEEDED closure → 0 unresolved
sha1sum (all blobs) → blob_sha1.txt
```

## 9. Assumptions

1. Stock RTAS31.68-66-3 is the single source of truth; the dump was cross-verified against the live device (file tables + SHA-1 spot checks match).
2. Vendor/etc configs are extracted as stock copy-files (fstab, init rc, audio/camera/wifi/bt configs, vintf fragments) — the device tree can override individual ones later.
3. Moto/Unisoc apps are re-signed with the LineageOS platform cert at build (standard `android_app_import` behavior; none use PRESIGNED).
4. `libhidltransport.so`/`libhwbinder.so` are extracted because stock ships them in vendor and stock binaries link them; VNDK v30 also provides them (harmless overlap).
5. The kernel deliverable (socko modules, defconfig, DTB) is handled by the separate kernel workstream; this report relies on its conclusions for module correlation.

## 10. Unresolved issues / environment notes

1. **C: drive is 100% full** — the WSL ext4 VHDX cannot grow; heavy artifacts were deliberately placed on G: via symlinks (`~/lineage/vendor/motorola/java` → G:, `~/g20dump` → dump). Freeing C: is required before any actual LineageOS build in WSL.
2. ADB-mode vendor extraction is impossible on a stock user build (SELinux, §4a) — this is a stock-policy fact, not a defect; the extractor defaults to adb as required and documents the dump path. On rooted/eng builds adb mode works fully.
3. extract-utils 18.1 quirks (upstream, not fixed here): unquoted `get_file` arguments (spaces in SRC/TMPDIR paths break it) and no `/system/system` fallback for system-as-root adb pulls.
4. `wcnmodem` / `pm_sys` partition images are not in the local firmware package (see §3) — required on-device for WiFi/BT/sensorhub; do not lose them if the device is ever wiped.
5. Deodex path unexercised (all APKs carry native dex); `zip`/`java` must exist on the build host for the generic pipeline (standard LineageOS build deps).
6. This deliverable is the extraction system only: the device tree (`BoardConfig`, overlay/manifest wiring, `/odm` symlink, 32-bit binder, sepolicy) is the next porting step and is intentionally out of scope.

## 11. Reproducibility

A developer with a Moto G20 XT2128-1 on RTAS31.68-66-3, unlocked bootloader, working ADB, and this `~/lineage` tree reproduces the result with:

```bash
cd ~/lineage/device/motorola/java
./extract-files.sh          # from the device: system_ext/system/product/vendor-etc subset
./extract-files.sh <dump>   # full vendor set from a firmware dump (see _analysis/tools/extract_dump.py)
./setup-makefiles.sh
```

The blob list is deterministic (LC_ALL=C-sorted, section-organized) and pinned-hash support (`|sha1`) is available; `blob_sha1.txt` contains the reference hashes for all 1832 blobs from RTAS31.68-66-3.

---

## EXTRACTION STATUS: GREEN

- Extractor implemented, syntax-validated, and **actually tested against both the stock device (ADB) and the firmware dump**; dump-mode extraction is 100% complete (1832/1832, 0 missing, 0 extra).
- Every included blob is evidence-backed (partition provenance + DT_NEEDED closure with 0 unresolved dependencies); nothing invented; exclusions documented with evidence.
- No blob fixups required at this API level; no stock firmware, kernel, or device state was modified; nothing was flashed.
