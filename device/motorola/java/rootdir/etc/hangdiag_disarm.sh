#!/system/bin/sh
# hangdiag_disarm: complete diagnostic teardown after a SUCCESSFUL boot.
# Triggered by init on sys.boot_completed=1 (bootlog.rc). Uses the kernel's
# official disable path for the monitor, then clears the misc flag and the
# one-shot BCB command — only those bytes, nothing else.
echo off > /proc/monitor_enable 2>/dev/null
dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=12 seek=65536 conv=notrunc 2>/dev/null
dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=32 seek=0 conv=notrunc 2>/dev/null
echo "bootlog: diagnostic mode fully disarmed after successful boot"
