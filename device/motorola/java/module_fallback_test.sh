#!/bin/bash
FB="/media/miguelfxx/3d127275-458d-41b3-b185-f5b7092cf903/lineage/device/motorola/java/rootdir/bin/module_fallback.sh"
MISC_FILE="/tmp/test_misc_partition.img"
TEST_SOCKO="/tmp/test_socko_fb"
PASS=0 FAIL=0
setup() {
    dd if=/dev/zero of="$MISC_FILE" bs=1024 count=2048 2>/dev/null
    rm -rf "$TEST_SOCKO"; mkdir -p "$TEST_SOCKO/recon" "$TEST_SOCKO/stock"
    for m in sprdwl_ng sprdbt_tty; do
        echo "socko_current_$m" > "$TEST_SOCKO/${m}.ko"
        echo "recon_$m" > "$TEST_SOCKO/recon/${m}.ko"
        echo "stock_$m" > "$TEST_SOCKO/stock/${m}.ko"
    done
}
cleanup() { rm -f "$MISC_FILE" /tmp/.fb_write.* "$TEST_SOCKO"/.fb_write.*; rm -rf "$TEST_SOCKO"; }
read_table() { dd if="$MISC_FILE" bs=512 skip=131 count=1 2>/dev/null | tr -d '\0'; }
boot() { FB_VERIFY_TRIES=1 FB_VERIFY_INTERVAL=0 FB_DRV_PRESENT=1 FB_TMP_DIR="$TEST_SOCKO" FB_MISC_OVERRIDE="$MISC_FILE" FB_SOCKO_OVERRIDE="$TEST_SOCKO" FB_RECON_DIR="$TEST_SOCKO/recon" FB_STOCK_DIR="$TEST_SOCKO/stock" timeout 10 sh "$FB" boot 2>&1; }
run() { FB_VERIFY_TRIES=1 FB_VERIFY_INTERVAL=0 FB_DRV_PRESENT=1 FB_TMP_DIR="$TEST_SOCKO" FB_MISC_OVERRIDE="$MISC_FILE" FB_SOCKO_OVERRIDE="$TEST_SOCKO" FB_RECON_DIR="$TEST_SOCKO/recon" FB_STOCK_DIR="$TEST_SOCKO/stock" timeout 10 sh "$FB" "$@" 2>&1; }
assert_has() { if echo "$2" | grep -q "$3"; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 — missing '$3'"; echo "  got: $(echo "$2" | head -3)"; FAIL=$((FAIL+1)); fi; }
assert_not() { if ! echo "$2" | grep -q "$3"; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 — unexpected '$3'"; FAIL=$((FAIL+1)); fi; }
assert_eq() { if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 — got '$2' want '$3'"; FAIL=$((FAIL+1)); fi; }

echo "=========================================="
echo " Module Fallback Test Harness"
echo "=========================================="

echo ""; echo "--- T1: Fresh boot ---"
setup; OUT=$(boot); TABLE=$(read_table)
assert_has "T1: magic" "$TABLE" "FBMOD_v1"
assert_has "T1: LOADING NONE" "$TABLE" "LOADING NONE"
assert_has "T1: sprdwl_ng REBUILT" "$TABLE" "sprdwl_ng REBUILT"
assert_has "T1: sprdbt_tty REBUILT" "$TABLE" "sprdbt_tty REBUILT"
assert_has "T1: boot complete" "$OUT" "boot complete"

echo ""; echo "--- T2: Crash during sprdwl_ng init ---"
TABLE=$(read_table | sed 's/LOADING NONE/LOADING sprdwl_ng/')
dd if=/dev/zero of="$MISC_FILE" bs=512 seek=131 count=1 conv=notrunc 2>/dev/null
printf '%s' "$TABLE" | dd of="$MISC_FILE" bs=512 seek=131 conv=notrunc 2>/dev/null
OUT=$(boot); TABLE=$(read_table)
assert_has "T2: crash detected" "$OUT" "failed to complete init"
assert_has "T2: sprdwl_ng still REBUILT (below threshold)" "$TABLE" "sprdwl_ng REBUILT"
assert_has "T2: fail_count=1" "$TABLE" "f=1"
assert_has "T2: LOADING cleared" "$TABLE" "LOADING NONE"
assert_has "T2: sprdbt_tty UNAFFECTED" "$TABLE" "sprdbt_tty REBUILT"

echo ""; echo "--- T3: sprdbt_tty crash doesn't affect sprdwl_ng ---"
TABLE=$(read_table | sed 's/LOADING NONE/LOADING sprdbt_tty/')
dd if=/dev/zero of="$MISC_FILE" bs=512 seek=131 count=1 conv=notrunc 2>/dev/null
printf '%s' "$TABLE" | dd of="$MISC_FILE" bs=512 seek=131 conv=notrunc 2>/dev/null
OUT=$(boot); TABLE=$(read_table)
assert_has "T3: sprdbt_tty REBUILT (below threshold)" "$TABLE" "sprdbt_tty REBUILT"
assert_has "T3: sprdwl_ng still REBUILT" "$TABLE" "sprdwl_ng REBUILT"

echo ""; echo "--- T4: STOCK persists across 3 boots ---"
for i in 1 2 3; do boot > /dev/null 2>&1; done
TABLE=$(read_table)
assert_has "T4: sprdwl_ng REBUILT" "$TABLE" "sprdwl_ng REBUILT"
assert_has "T4: sprdbt_tty REBUILT" "$TABLE" "sprdbt_tty REBUILT"

echo ""; echo "--- T5: --clear sprdwl_ng ---"
OUT=$(run --clear sprdwl_ng); TABLE=$(read_table)
assert_has "T5: sprdwl_ng REBUILT" "$TABLE" "sprdwl_ng REBUILT"
assert_has "T5: sprdbt_tty NOT cleared" "$TABLE" "sprdbt_tty REBUILT"

echo ""; echo "--- T6: Corrupt magic → fresh init ---"
dd if=/dev/zero of="$MISC_FILE" bs=512 seek=131 count=1 conv=notrunc 2>/dev/null
OUT=$(boot); TABLE=$(read_table)
assert_has "T6: magic restored" "$TABLE" "FBMOD_v1"
assert_has "T6: modules REBUILT" "$TABLE" "sprdwl_ng REBUILT"

echo ""; echo "--- T7: --clear-all ---"
OUT=$(run --clear-all); TABLE=$(read_table)
assert_has "T7: all REBUILT" "$TABLE" "sprdwl_ng REBUILT"

echo ""; echo "--- T8: --status ---"
OUT=$(run --status)
assert_has "T8: status has sprdwl_ng" "$OUT" "sprdwl_ng"
assert_has "T8: status has REBUILT" "$OUT" "REBUILT"

echo ""; echo "--- T9: boot stages recon build onto socko ---"
setup
OUT=$(boot)
assert_has "T9: staged recon sprdwl_ng" "$(cat $TEST_SOCKO/sprdwl_ng.ko)" "recon_sprdwl_ng"
assert_has "T9: staged recon sprdbt_tty" "$(cat $TEST_SOCKO/sprdbt_tty.ko)" "recon_sprdbt_tty"

echo ""; echo "--- T10: verify records ok when driver present ---"
setup; boot > /dev/null 2>&1
OUT=$(run verify); TABLE=$(read_table)
assert_has "T10: verify ok" "$TABLE" "sprdwl_ng REBUILT f=0 o=1"

echo ""; echo "--- T11: verify records failure when driver absent ---"
setup; boot > /dev/null 2>&1
OUT=$(FB_VERIFY_TRIES=1 FB_VERIFY_INTERVAL=0 FB_DRV_PRESENT=0 FB_TMP_DIR="$TEST_SOCKO" FB_MISC_OVERRIDE="$MISC_FILE" FB_SOCKO_OVERRIDE="$TEST_SOCKO" FB_RECON_DIR="$TEST_SOCKO/recon" FB_STOCK_DIR="$TEST_SOCKO/stock" timeout 10 sh "$FB" verify 2>&1); TABLE=$(read_table)
assert_has "T11: hal_load_failed recorded" "$TABLE" "hal_load_failed"

echo ""; echo "--- T12: 3 absent boots flip only the failed module to STOCK staging ---"
setup; boot > /dev/null 2>&1
for i in 1 2 3; do FB_VERIFY_TRIES=1 FB_VERIFY_INTERVAL=0 FB_DRV_PRESENT="sprdwl_ng=0 sprdbt_tty=1" FB_TMP_DIR="$TEST_SOCKO" FB_MISC_OVERRIDE="$MISC_FILE" FB_SOCKO_OVERRIDE="$TEST_SOCKO" FB_RECON_DIR="$TEST_SOCKO/recon" FB_STOCK_DIR="$TEST_SOCKO/stock" timeout 10 sh "$FB" verify >/dev/null 2>&1; done
OUT=$(boot)
assert_has "T12: staged stock sprdwl_ng" "$(cat $TEST_SOCKO/sprdwl_ng.ko)" "stock_sprdwl_ng"
assert_has "T12: sprdbt_tty keeps recon" "$(cat $TEST_SOCKO/sprdbt_tty.ko)" "recon_sprdbt_tty"

echo ""; echo "--- T13: lowercase none marker never treated as module ---"
setup; boot > /dev/null 2>&1
TABLE=$(read_table | sed 's/LOADING NONE/LOADING none/')
dd if=/dev/zero of="$MISC_FILE" bs=512 seek=131 count=1 conv=notrunc 2>/dev/null
printf '%s' "$TABLE" | dd of="$MISC_FILE" bs=512 seek=131 conv=notrunc 2>/dev/null
OUT=$(boot); TABLE=$(read_table)
assert_not "T13: no bogus module entry" "$TABLE" "none FAILED"
assert_has "T13: table intact" "$TABLE" "sprdwl_ng REBUILT"

echo ""; echo "--- T14: self-healing after entry loss ---"
setup; boot > /dev/null 2>&1
TABLE=$(read_table | sed '/^M sprdwl_ng/d')
dd if=/dev/zero of="$MISC_FILE" bs=512 seek=131 count=1 conv=notrunc 2>/dev/null
printf '%s' "$TABLE" | dd of="$MISC_FILE" bs=512 seek=131 conv=notrunc 2>/dev/null
OUT=$(boot); TABLE=$(read_table)
assert_has "T14: rebuilt missing entry" "$OUT" "rebuilding fresh"
assert_has "T14: sprdwl_ng restored" "$TABLE" "sprdwl_ng REBUILT"

echo ""; echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
cleanup; exit $(( FAIL > 0 ? 1 : 0 ))
