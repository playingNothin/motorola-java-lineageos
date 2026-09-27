#!/system/bin/sh
# bootlog_diag: persistent kernel console capture, DIAGNOSTIC SESSION ONLY.
# Started by init at post-fs on every boot; exits immediately unless the
# developer armed diagnostic mode (HANGDIAG_ON flag at misc offset 65536,
# set from Recovery). The capture is bounded to 32 MiB and is stopped by
# init (hangdiag_disarm) after a successful boot, or ends with the device
# on a hung boot — preserving the log on the metadata partition.
if ! dd if=/dev/block/by-name/misc bs=512 skip=128 count=1 2>/dev/null | grep -q HANGDIAG_ON; then
	exit 0
fi
if ! grep -q " /metadata " /proc/mounts; then
	mount -t ext4 /dev/block/mmcblk0p62 /metadata
fi
mkdir -p /metadata/bootlog
echo "=== bootlog: HANGDIAG session started $(date) ===" >> /metadata/bootlog/console.log
# v2: userspace logcat capture alongside the kmsg capture (see
# docs/project_knowledge/BOOTLOG_LOGCAT_HOWTO.md). The pstore pmsg ring only
# keeps the LAST 32 KB of logd output (it wraps — iter9 lost the first HAL
# failure messages and the zygote abort reason to it). This one is rotating
# (2 MiB x 4) so repeated armed boots cannot fill metadata. It waits for
# logd's control socket (bootlog_diag starts at post-fs, logd comes up later
# with class core), and init kills it together with the service when
# hangdiag_disarm stops bootlog_diag after sys.boot_completed=1.
( while [ ! -S /dev/socket/logd ]; do sleep 1; done; \
  logcat -b all -v threadtime -f /metadata/bootlog/logcat.log -r 2048 -n 4 ) &
# bounded capture: head exits after 32 MiB, cat then dies on SIGPIPE
exec sh -c 'cat /dev/kmsg | head -c 33554432' >> /metadata/bootlog/console.log
