#!/usr/bin/env python3
"""
Inject essential device nodes into a newc-format cpio archive (in place).

This kernel has no devtmpfs and the recovery ramdisk ships an empty /dev.
At PID-1 time, bionic's getentropy() fallback opens /dev/urandom; without
that node every external binary (toybox mknod/mount/...) aborts with
SIGABRT before it can do anything. The kernel's initramfs unpacker creates
these nodes as root, so embedding them in the cpio needs no host root.

Entries are appended before TRAILER!!!; later entries override earlier
ones during unpack, and all five paths are absent from the source archive.
Idempotent: re-running adds nothing if nodes already exist.
"""
import struct, sys

# name -> (mode, rmajor, rminor); mode = S_IFCHR/S_IFBLK | 0600
NODES = [
    ("dev/null",              0o020600, 1,   3),
    ("dev/kmsg",              0o020600, 1,   11),
    ("dev/urandom",           0o020600, 1,   9),
    ("dev/random",            0o020600, 1,   8),
    ("dev/block",             0o040750, 0,   0),   # directory
    ("dev/block/mmcblk0p62",  0o060600, 259, 55),
]

def parse_name(data, off, namesize):
    return data[off:off+namesize-1].decode()

def pad4(n):
    return (n + 3) & ~3

def entry(name, mode, rmaj, rmin, ino, fsize=0):
    nb = name.encode() + b"\0"
    hdr = b"070701" + b"".join(
        b"%08X" % v for v in (ino, mode, 0, 0, 1, 0, fsize, 0, 0, rmaj, rmin, len(nb), 0))
    out = hdr + nb
    out += b"\0" * (pad4(len(hdr) + len(nb)) - len(hdr) - len(nb))
    out += b"\0" * (pad4(fsize) - fsize)  # no data
    return out

def main(path):
    data = open(path, "rb").read()
    if data[:6] not in (b"070701", b"070702"):
        print("inject_devnodes: not a newc cpio: %s" % path)
        return 1
    # collect existing names; locate TRAILER!!! entry
    existing = set()
    trailer_i = -1
    i = 0
    while i + 110 <= len(data):
        if data[i:i+6] not in (b"070701", b"070702"):
            break
        namesize = int(data[i+94:i+102], 16)
        fsize = int(data[i+54:i+62], 16)
        name = parse_name(data, i+110, namesize)
        if name == "TRAILER!!!":
            trailer_i = i
            break
        existing.add(name)
        i += pad4(110 + namesize) + pad4(fsize)
    add = [(n, m, a, b) for n, m, a, b in NODES if n not in existing]
    if not add:
        print("inject_devnodes: nothing to add")
        return 0
    assert trailer_i >= 0, "trailer not found"
    namesize = int(data[trailer_i+94:trailer_i+102], 16)
    fsize = int(data[trailer_i+54:trailer_i+62], 16)
    trailer_len = pad4(110 + namesize) + pad4(fsize)
    trailer = data[trailer_i:trailer_i+trailer_len]

    out = data[:trailer_i]
    ino = 100000
    for n, m, a, b in add:
        out += entry(n, m, a, b, ino)
        ino += 1
        print("inject_devnodes: + %s (%d %d:%d)" % (n, m, a, b))
    out += trailer
    open(path, "wb").write(out)
    print("inject_devnodes: wrote %s (%d -> %d bytes)" % (path, len(data), len(out)))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
