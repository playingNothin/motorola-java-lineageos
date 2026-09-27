#!/usr/bin/env python3
"""
vendor_bp_fixups.py - post-generation fixups for vendor/motorola/java/Android.bp
                    + java-vendor.mk (Moto G20 java, LineageOS 18.1).

Corrects four defects of the LineageOS 18.1 extract-utils generator, all found
by actually building:

1. Duplicate module names. The generator emits one module per file basename;
   on this device several basenames exist more than once (cross-partition
   copies like vendor/lib + system_ext/lib of the same sprd HAL stub, and
   stock files sharing a basename such as the clearkey/widevine drm
   services). Every definition after the first is renamed (name + __fixupN),
   given `stem` = the original filename, given the correct partition flag,
   and appended to the vendor PRODUCT_PACKAGES list.

2. Module names colliding with platform modules (vendor_bp_collisions.txt:
   vendor copies of AOSP codecs/utilities/HAL impls whose names exist in the
   platform). Soong either auto-pairs them with the platform source module
   (failing on variations the prebuilt cannot provide: host, recovery, 32-bit
   ...) or, when renamed, double-registers the same vendor install path at
   kati time ("overriding commands for target"). For every such collision the
   platform provably installs the same vendor path (out/soong bridge
   analysis), so our prebuilt block is DELETED and its PRODUCT_PACKAGES
   reference dropped - the platform-built equivalent provides the file.
   SPRD-specific implementations (ums512/sprd/unisoc-named) never collide and
   are untouched.

3. `prefer: true` on vendor prebuilts: a preferred prebuilt hijacks every
   consumer of a same-named platform module (including host variations).
   Stripped everywhere (remaining prebuilts are unique vendor-only names).

4. The 9 sh_binary modules and 20 readme "binaries" were converted to plain
   copy-files in proprietary-files.txt (extract-utils emits S-era sh_binary
   syntax the 18.1 Soong rejects); nothing to do here for those.

Run after every setup-makefiles.sh regeneration:
    python3 vendor_bp_fixups.py <ANDROID_ROOT>
"""
import re, sys, collections, os

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../..")
bp_path = os.path.join(root, "vendor/motorola/java/Android.bp")
mk_path = os.path.join(root, "vendor/motorola/java/java-vendor.mk")
seed_path = os.path.join(os.path.dirname(__file__), "vendor_bp_collisions.txt")

collisions = set()
if os.path.exists(seed_path):
    collisions.update(l.strip() for l in open(seed_path) if l.strip())

text = open(bp_path).read()
block_re = re.compile(r'(?m)^(cc_prebuilt_library_shared|cc_prebuilt_binary|sh_binary|android_app_import|dex_import) \{\n(.*?)^\}\n', re.S)


def srcfile_of(body):
    m = re.search(r'srcs: \["([^"]+)"\]', body)
    if m:
        return m.group(1)
    m = re.search(r'android_arm64: \{\s*srcs: \["([^"]+)"\]', body)
    if m:
        return m.group(1)
    m = re.search(r'android_arm: \{\s*srcs: \["([^"]+)"\]', body)
    if m:
        return m.group(1)
    return ""


names = collections.defaultdict(list)
blocks = list(block_re.finditer(text))
for i, m in enumerate(blocks):
    n = re.search(r'name: "([^"]+)"', m.group(2)).group(1)
    names[n].append(i)

# SPRD-specific implementations whose names also exist as make-defined
# platform modules (module-id collision): rename like the duplicates.
MK_RENAME = ["gralloc.default", "hostapd", "libbt-vendor", "libstagefrighthw",
             "libwifi-hal", "test_lib", "wpa_supplicant"]
# Same-named AOSP app the platform provides; drop our copy.
MK_DROP = ["WAPPushManager"]

renamed = []
dropped = []
out = []
pos = 0
counter = collections.Counter()
for i, m in enumerate(blocks):
    out.append(text[pos:m.start()])
    typ, body = m.group(1), m.group(2)
    name = re.search(r'name: "([^"]+)"', body).group(1)
    if name in collisions or name in MK_DROP:
        # platform builds the same vendor path (or the same app) from source;
        # drop our block
        dropped.append(name)
        pos = m.end()
        continue
    if name in MK_RENAME:
        counter[name] += 1
        new = f"{name}__v"
        srcfile = srcfile_of(body)
        body = re.sub(r'name: "[^"]+"', f'name: "{new}"', body, count=1)
        body = re.sub(r'(name: "[^"]+",\n)', lambda mm: mm.group(1) + f'\tstem: "{name}",\n', body, count=1)
        renamed.append(new)
        out.append(f"{typ} {{\n{body}\n}}\n")
        pos = m.end()
        continue
    if len(names[name]) > 1 and i != names[name][0]:
        counter[name] += 1
        new = f"{name}__fixup{counter[name]}"
        srcfile = srcfile_of(body)
        stem = os.path.basename(srcfile)
        if typ == "cc_prebuilt_library_shared" and stem.endswith(".so"):
            stem = stem[:-3]  # soong appends the .so suffix itself
        body = re.sub(r'name: "[^"]+"', f'name: "{new}"', body, count=1)
        body = re.sub(r'(name: "[^"]+",\n)', lambda mm: mm.group(1) + f'\tstem: "{stem}",\n', body, count=1)
        if "/proprietary/system_ext/" in srcfile:
            body = re.sub(r'\n$', '\n\tsystem_ext_specific: true,', body, count=1)
        elif "/proprietary/system/" in srcfile:
            body = re.sub(r'\n$', '\n\tsystem_specific: true,', body, count=1)
        if "/egl/" in srcfile:
            body = re.sub(r'\n$', '\n\trelative_install_path: "egl",', body, count=1)
        renamed.append(new)
        out.append(f"{typ} {{\n{body}\n}}\n")
    else:
        out.append(m.group(0))
    pos = m.end()
out.append(text[pos:])
text = "".join(out)
text = text.replace("\n\tprefer: true,", "")
open(bp_path, "w").write(text)

# Remove dropped entries from the PRODUCT_PACKAGES list. A dropped line must
# be deleted outright (never replaced by a trailing-backslash comment: a
# backslash-newline continues a make comment into the next line, which would
# silently swallow the following package entry).
mk = open(mk_path).read()
# Rewrite package-list references for renamed make-level collisions.
for n in MK_RENAME:
    mk = re.sub(r'(?m)^    ' + re.escape(n) + r'( \\|)$', f'    {n}__v\\1', mk)
for n in dropped:
    mk = re.sub(r'(?m)^    ' + re.escape(n) + r'( \\|)$\n?', '', mk)
open(mk_path, "w").write(mk)

if renamed:
    with open(mk_path, "a") as f:
        f.write("\n# Extra prebuilt modules for duplicate-basename stock files\n")
        f.write("# (renamed by device/motorola/java/vendor_bp_fixups.py; each keeps its\n")
        f.write("# stock filename via stem)\nPRODUCT_PACKAGES += \\\n")
        f.write(" \\\n".join(f"    {n}" for n in renamed) + "\n")
print(f"collision drops: {len(dropped)}, duplicate renames: {len(renamed)}")
