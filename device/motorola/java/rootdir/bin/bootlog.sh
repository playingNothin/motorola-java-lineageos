#!/system/bin/sh
# Boot console recorder v3 (DEBUG ONLY — remove after bring-up).
# Two independent persistent captures of the kernel log buffer:
#   1. /metadata/bootlog/console.log — formats+mounts the (blank) metadata
#      partition directly BY DEVICE NODE (no by-name symlink dependency —
#      ueventd may not have created symlinks this early).
#   2. /cache/bootlog/console.log — waits for the second-stage mount_all.
# /dev/kmsg replays the entire printk buffer on open, so both captures include
# everything from boot start. Each step is announced to kmsg so the captures
# also show the logger's own progress.

# 1. metadata capture (available from early-init)
(
    n=0
    while [ ! -b /dev/block/mmcblk0p62 ] && [ $n -lt 20 ]; do
        sleep 1; n=$((n+1))
    done
    echo "bootlog: metadata node ready after ${n}s" > /dev/kmsg
    mke2fs -F -t ext4 /dev/block/mmcblk0p62 2>/dev/null
    mkdir -p /metadata
    mount -t ext4 /dev/block/mmcblk0p62 /metadata 2>/dev/null
    echo "bootlog: metadata mount rc=$?" > /dev/kmsg
    mkdir -p /metadata/bootlog
    cat /dev/kmsg >> /metadata/bootlog/console.log
    echo "bootlog: metadata capture running" > /dev/kmsg
) &

# 2. /cache capture (available after second-stage mount_all)
(
    n=0
    while [ ! -d /cache/lost+found ] && [ $n -lt 90 ]; do
        sleep 1; n=$((n+1))
    done
    echo "bootlog: /cache ready after ${n}s" > /dev/kmsg
    mkdir -p /cache/bootlog
    cat /dev/kmsg >> /cache/bootlog/console.log
    echo "bootlog: /cache capture running" > /dev/kmsg
) &

wait
