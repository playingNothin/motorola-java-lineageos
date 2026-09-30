# Motorola Moto G20 (java) — LineageOS 18.1 device tree (first pass)

Target: `lineage_java-userdebug`, Android 11 / API 30, Unisoc UMS512 (Tiger T700, sharkl5pro), board p352.

## Evidence basis

Every value in this tree is derived from verified sources — see
`_analysis/report/` (HAL map, VINTF closure, runtime closures, SELinux port map,
AVB forensics) and `_analysis/runtime_recon/` (rooted-device captures):

| Source | Key facts |
|---|---|
| `/proc/cmdline` (root) | `androidboot.hardware=ums512_1h10`, `dtbo_idx=0`, panel `lcd_ili7806s90_txd_mipi_hd` 1600x720, `veritymode=enforcing`, slot suffix |
| `/dev/block/by-name` (root) | full A/B map: boot 43/44, dtb 47/48, dtbo 49/50, super 51, vbmeta 60/61 (+4 per-partition vbmetas), metadata 62, socko 56/57, odmko 58/59 |
| LP metadata (super.img) | super 5,452,595,200 B; system_a 1,332,715,520; system_ext_a 330,301,440; vendor_a 818,937,856; product_a 2,215,905,280 |
| fstab (identical p352/ums512_1h10) | dynamic first-stage mounts, f2fs userdata w/ metadata-encrypted FBE v2, `avb=socko`, `avb=odmko`, journey/prodnv/cache mounts |
| boot.img v2 header | kernel 19,017,744 B, ramdisk 9,184,020 B, page 2048, DTB in v1 recovery_dtbo slot, cmdline `console=ttyS1,115200n8 buildvariant=user` |
| lshal (root) | all stock HALs registered: audio@6.0, camera@2.4, sensors@1.0, composer@2.1, allocator@4.0, bt@1.1, wifi, gnss@2.1, keymaster@4.1-unisoc, gatekeeper-trusty, boot@1.1, wcn@1.0, vdsp, broadcastradio, thermal, usb, memtrack, health, drm (widevine+clearkey), fingerprint |
| vendor policy (prebuilt) | `vendor_sepolicy.cil` + `plat_pub_versioned.cil` (plat target 30.0) + all contexts; custom exec types (modem_control_exec, tee_exec, hal_keymaster_unisoc_exec, wcnd_exec…) |
| props | vendor build.prop/default.prop + ramdisk prop.default distilled into device.mk |

## Layout

- `BoardConfig.mk` — platform, arch (64/32), boot image v2 + offsets, dynamic partition sizes,
  AVB, VNDK 30, sepolicy dirs, recovery-in-boot, f2fs, metadata partition
- `device.mk` — fstab/avb-keys/vintf copies, stock property set, f2fs tools
- `lineage_java.mk` + `AndroidProducts.mk` + `vendorsetup.sh` — product wiring
- `rootdir/etc/fstab.{ums512_1h10,p352}` — stock fstab (both names; `ro.hardware=ums512_1h10`)
- `rootdir/avb/*.avbpubkey` — GSI keys referenced by the fstab system entry (from stock ramdisk)
- `vintf/manifest.xml` — stock root vendor manifest (fragment manifests ship as blobs)
- `sepolicy/vendor/` — stock vendor + odm policy prebuilts (contexts + CIL; see notes)
- `prebuilt/kernel/Image` — stock RTAS31.68-66-3 kernel (sha256 dd836ba3…; the kernel that
  boots the device; socko module CRCs verified 667/667 against it)
- `prebuilt/kernel/dtb` — stock base DTB (from boot.img recovery_dtbo slot)
- `prebuilt/dtbo.img` — stock dtbo image (AVB-verified, chain slot 6)
- `proprietary-files.txt` + `extract-files.sh` + `setup-makefiles.sh` — validated extraction
  (1832/1832 from the rooted device)

## Vendor init flow (no device-tree init.rc needed for first pass)

init imports `/vendor/etc/init/hw/init.${ro.hardware}.rc` → `init.ums512_1h10.rc` is absent in
vendor; the operative chain on stock is `init.p352.rc` (imports `init.${ro.hardware}.usb.rc` —
also absent, file names are p352/p353/p354/ums512_*; the `hw/` scripts import by exact name so
the p352 one must be reached). Verify which file init actually imports at first boot and, if
needed, add a tiny `init.ums512_1h10.rc` that imports `init.p352.rc`. All service rc files
under `/vendor/etc/init/*.rc` are imported automatically by init and ship as blobs.

## Known deviations / open items (BUILD-VERIFY list)

1. **Vendor sepolicy wiring** — contexts ship in `BOARD_VENDOR_SEPOLICY_DIRS` (standard);
   `vendor_sepolicy.cil` / `plat_pub_versioned.cil` / `odm_sepolicy.cil` are stock prebuilt CIL
   dropped in the same dir. Verify the 18.1 sepolicy build accepts prebuilt CIL in policy dirs;
   if not, install them as copy-files to `$(TARGET_COPY_OUT_VENDOR)/etc/selinux/` instead and
   confirm `libsepol` binds the platform-version mapping (`plat_sepolicy_vers.txt` = 30.0).
2. **DTB slot** — stock places the DTB in the v1 `recovery_dtbo` field; pass
   `--recovery_dtbo prebuilt/kernel/dtb` via BOARD_MKBOOTIMG_ARGS if the build's boot image
   lacks it (mkbootimg supports it for header v1/v2).
3. **AVB chain slots** — stock uses per-partition rollback slots (1..14) and separate
   vbmeta_system/_ext/_vendor/_product partitions. This tree uses the LineageOS
   `BOARD_AVB_VBMETA_SYSTEM` grouping (one slot) and the default test key — sufficient for an
   unlocked device (verification skipped); replicate the exact 14-slot layout only if the
   stock vbmeta must be bit-compatible.
4. **socko/odmko/pm_sys/modem AVB chains** — stock images stay stock-signed; with a test-key
   vbmeta their `avb=` fstab mounts fail-soft in orange state (unlocked). Do not ship test-key
   chain descriptors for them if staying stock-adjacent.
5. **`BOARD_SYSTEMIMAGE_EXTRA_SYMLINKS`** syntax (socko/odmko) — verify at build; fallback is a
   rootdir post-fs script or init symlink.
6. **Modem/WCN runtime** — `modem_control`, `urild`, `engpc`, `connmgr`, wcn HAL are all
   stock-blob driven; the lte `l-fixnv1/2`, `l-runtimenv1/2` NV partitions must remain intact.
7. **Recovery touch** — recovery uses the same touch modules (socko); touch may be absent in
   recovery until modules load; add `init.recovery` module loading if needed.

## Not copied from stock (regenerated by the build)

build.prop / default.prop / vintf root manifest (adapted) / platform policy / recovery binary /
init binary / boot ramdisk framework files. Everything vendor-specific ships as blobs.
