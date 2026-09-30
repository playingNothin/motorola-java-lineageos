#!/system/bin/sh
# module_fallback.sh — persistent per-module fallback / canary system
#
# Storage: misc partition sector 131 (offset 67072), text format.
# Coexists with HANGDIAG (sectors 128-130) and BCB (sector 0).
#
# Usage:
#   module_fallback.sh boot          — called from init at post-fs-data
#   module_fallback.sh verify        — called from init at sys.boot_completed
#   module_fallback.sh --status      — print the fallback table
#   module_fallback.sh --clear NAME  — re-enable REBUILT for a module
#   module_fallback.sh --clear-all   — reset all modules to REBUILT
#
# Loading contract (matches the stock device): the vendor HALs load
# sprdwl_ng / sprdbt_tty themselves via finit_module() from
# $SOCKO/<module>.ko. The canary NEVER insmods them — a preloaded module
# makes the HAL's own finit_module fail with EEXIST and kills the radio.
# The canary stages the right .ko file onto socko (remount rw) according
# to the per-module state, then verifies after boot whether the HAL
# actually got the driver up, recording ok/fail on misc.

MISC=""
FB_SECTOR=131
FB_MAGIC="FBMOD_v1"
FB_FAIL_THRESHOLD=3
FB_MODULES="sprdwl_ng sprdbt_tty"
FB_RECON_DIR="${FB_RECON_DIR:-/system/lib/modules/recon}"
FB_STOCK_DIR="${FB_STOCK_DIR:-/system/lib/modules/stock}"

# test overrides (host-side harness sets these)
[ -n "$FB_MISC_OVERRIDE" ] && MISC="$FB_MISC_OVERRIDE"
[ -n "$FB_SOCKO_OVERRIDE" ] && SOCKO="$FB_SOCKO_OVERRIDE"
SOCKO="${SOCKO:-/mnt/vendor/socko}"

find_misc() {
    [ -n "$MISC" ] && [ -e "$MISC" ] && return 0
    for m in /dev/block/by-name/misc /dev/block/mmcblk0p3; do
        [ -e "$m" ] && MISC="$m" && return 0
    done
    return 1
}

fb_read() {
    dd if="$MISC" bs=512 skip=$FB_SECTOR count=1 2>/dev/null | tr -d '\0'
}

fb_write() {
    # NO scratch file: /tmp does not exist on-device and /dev rejects
    # file creation (devtmpfs SELinux) — both silently killed every
    # write from earlier builds. Compose the padded 512-byte block in a
    # pipeline instead; works from init, shell and recovery contexts.
    local len="$(printf '%s\n' "$1" | wc -c)"
    local pad=$((512 - len))
    [ "$pad" -lt 0 ] && pad=0
    { printf '%s\n' "$1"; dd if=/dev/zero bs=1 count=$pad 2>/dev/null; } | \
        dd of="$MISC" bs=512 seek=$FB_SECTOR conv=notrunc 2>/dev/null
}

fb_check_magic() {
    fb_read | head -1 | grep -q "$FB_MAGIC"
}

fb_get_loading() {
    fb_read | grep "^LOADING " | head -1 | sed 's/^LOADING //' | tr -d ' \r\n'
}

fb_get_field() {
    fb_read | grep "^M $1 " | tr ' ' '\n' | grep "^$2" | head -1 | cut -d= -f2
}

fb_get_state() {
    fb_read | grep "^M $1 " | head -1 | awk '{print $3}'
}

fb_write_table() {
    # Rebuild the table preserving all entries
    local loading="$1"
    local entries=""
    for module in $FB_MODULES; do
        local line="$(fb_read | grep "^M $module ")"
        if [ -n "$line" ]; then
            entries="${entries}
${line}"
        fi
    done
    fb_write "${FB_MAGIC}
LOADING ${loading:-NONE}${entries}
END"
}

fb_set_module() {
    local module=$1 state=$2 fails=$3 oks=$4 last=$5
    # reject empty/garbage module names (mksh word-splitting of an
    # unquoted local assignment once produced bare-M table entries)
    case "$module" in
        ""|none|NONE) echo "module_fallback: refusing to record '$module'"; return 1 ;;
    esac
    local loading="$(fb_get_loading)"
    # Remove the old entry for this module
    local other_entries="$(fb_read | grep "^M " | grep -v "^M $module ")"
    local new_table="${FB_MAGIC}
LOADING ${loading}
M ${module} ${state} f=${fails} o=${oks} last=${last}"
    [ -n "$other_entries" ] && new_table="${new_table}
${other_entries}"
    new_table="${new_table}
END"
    fb_write "$new_table"
}

fb_clear_loading() {
    fb_write_table "NONE"
}

fb_record_failure() {
    local module=$1 reason=${2:-"unknown"}
    local f="$(fb_get_field "$module" "f=")"
    local o="$(fb_get_field "$module" "o=")"
    f=$(( ${f:-0} + 1 ))
    # Flip to STOCK staging only when the failure threshold is reached;
    # below it the module stays on the reconstructed build.
    if [ "$f" -ge "$FB_FAIL_THRESHOLD" ]; then
        fb_set_module "$module" "STOCK" "$f" "${o:-0}" "$reason"
    else
        fb_set_module "$module" "REBUILT" "$f" "${o:-0}" "$reason"
    fi
}

fb_record_ok() {
    local module=$1
    local f="$(fb_get_field "$module" "f=")"
    local o="$(fb_get_field "$module" "o=")"
    fb_set_module "$module" "REBUILT" "${f:-0}" "$(( ${o:-0} + 1 ))" "NONE"
}

fb_ensure_entries() {
    for module in $FB_MODULES; do
        if [ -z "$(fb_read | grep "^M $module ")"; ]; then
            fb_set_module "$module" "REBUILT" 0 0 "NONE"
        fi
    done
}

fb_handle_crash() {
    local loading="$(fb_get_loading)"
    # Empty or the none marker (either case) means the previous boot
    # finished loading cleanly — never treat it as a module name.
    case "$(echo "$loading" | tr 'a-z' 'A-Z')" in
        ""|NONE) return 0 ;;
    esac
    echo "module_fallback: '$loading' failed to complete init"
    fb_record_failure "$loading" "module_init_crash"
    fb_clear_loading
}

fb_stage_module() {
    local module=$1
    local state="$(fb_get_state "$module")"
    local src=""
    case "$state" in
        REBUILT) src="${FB_RECON_DIR}/${module}.ko" ;;
        STOCK)   src="${FB_STOCK_DIR}/${module}.ko" ;;
        *)       return 0 ;;
    esac
    [ -f "$src" ] || { echo "module_fallback: $src missing for $module"; return 1; }
    # Deploy the chosen build onto socko — the HAL loads it from there.
    [ -d "$SOCKO" ] || return 1
    if ! cmp -s "$src" "${SOCKO}/${module}.ko"; then
        mount -o remount,rw "$SOCKO" 2>/dev/null
        cp "$src" "${SOCKO}/${module}.ko" 2>/dev/null \
            && echo "module_fallback: staged $state $module onto socko"
        mount -o remount,ro "$SOCKO" 2>/dev/null
    fi
}

fb_insmod() {
    local module=$1
    local ko="${SOCKO}/${module}.ko"
    [ ! -f "$ko" ] && { echo "module_fallback: $ko not found"; return 1; }
    # Write the currently_loading marker
    local table="$(fb_read | sed "s/^LOADING .*$/LOADING ${module}/")"
    fb_write "$table"
    if [ -n "$FB_SKIP_INSOD" ] || insmod "$ko" 2>/dev/null; then
        fb_record_ok "$module"
        fb_clear_loading
        return 0
    fi
    # insmod can also fail when the driver is already active in the
    # kernel — either loaded earlier in boot or compiled in (=y build).
    # That is success, not a failure; record it so the canary does not
    # fall back to the stock module while the recon driver is running.
    if grep -q "^${module} " /proc/modules 2>/dev/null || fb_driver_present "$module"; then
        fb_record_ok "$module"
        fb_write "$(fb_read | sed "s/^\(M ${module} .*last=\).*/\1already_active/")"
        fb_clear_loading
        return 0
    fi
    fb_record_failure "$module" "insmod_failed"
    fb_clear_loading
    return 1
}

# Platform driver name per module (differs from the module name for
# some drivers: sprdwl_ng registers as sc2355, sprdbt_tty as mtty).
fb_driver_present() {
    local module=$1
    # harness override: FB_DRV_PRESENT=1/0 forces the answer globally,
    # or "module=0 module=1" pairs force it per module.
    case "$FB_DRV_PRESENT" in
        1|0) return "$((1 - $FB_DRV_PRESENT))" ;;
        *"$module="*)
            local pair want
            for pair in $FB_DRV_PRESENT; do
                case "$pair" in
                    "$module=0") return 1 ;;
                    "$module=1") return 0 ;;
                esac
            done
            ;;
    esac
    local drv
    case "$module" in
        sprdwl_ng)  drv=sc2355 ;;
        sprdbt_tty) drv=mtty ;;
        *)          drv="$module" ;;
    esac
    [ -d "/sys/bus/platform/drivers/${drv}" ]
}

do_boot() {
    find_misc || { echo "module_fallback: misc not found"; return 1; }
    if ! fb_check_magic; then
        echo "module_fallback: initialising fresh fallback table"
        local fresh="${FB_MAGIC}
LOADING NONE"
        for module in $FB_MODULES; do
            fresh="${fresh}
M ${module} REBUILT f=0 o=0 last=NONE"
        done
        fb_write "${fresh}
END"
    fi
    fb_handle_crash
    fb_ensure_entries
    # Stage the state-selected build for each module onto socko. The
    # HAL loads the module itself later in boot (finit_module) — the
    # canary must NOT insmod it here or the HAL gets EEXIST.
    for module in $FB_MODULES; do
        fb_stage_module "$module"
    done
    fb_selfcheck
    echo "module_fallback: boot complete (modules left to the HAL)"
}

# Post-boot verification: the HAL had its chance to load each module.
# A bound platform driver means the HAL load + probe worked; an absent
# driver accumulates a failure and eventually flips the module to STOCK
# staging (stock .ko deployed the same way, no reboot needed).
#
# The WiFi HAL's own failure-recovery unloads and reloads the driver a
# few times during bring-up, so a single absent snapshot would falsely
# record a failure. Poll the driver state for up to ~10 s and only
# record a failure when it never appears.
do_verify() {
    find_misc || return 1
    fb_check_magic || return 1
    for module in $FB_MODULES; do
        local state="$(fb_get_state "$module")"
        [ "$state" = "STOCK" ] && continue
        if fb_driver_present_wait "$module"; then
            fb_record_ok "$module"
        else
            echo "module_fallback: $module driver absent after boot"
            fb_record_failure "$module" "hal_load_failed"
        fi
    done
}

# Poll fb_driver_present; the first positive wins so a transient
# unload/reload gap in the middle is not counted as absence.
# FB_VERIFY_TRIES / FB_VERIFY_INTERVAL override the schedule (harness).
fb_driver_present_wait() {
    local module=$1
    local tries=${FB_VERIFY_TRIES:-5}
    local interval=${FB_VERIFY_INTERVAL:-2}
    local try=0
    while [ "$try" -lt "$tries" ]; do
        if fb_driver_present "$module"; then
            return 0
        fi
        try=$((try + 1))
        [ "$try" -lt "$tries" ] && sleep "$interval"
    done
    return 1
}

# Table self-healing: whatever corrupted the module entries on-device
# (20260929 build), detect it and rewrite a fresh table rather than
# propagating garbage.
fb_selfcheck() {
    local broken=0
    for module in $FB_MODULES; do
        [ -n "$(fb_read | grep "^M $module ")" ] || broken=1
    done
    [ "$broken" = "0" ] && return 0
    echo "module_fallback: table entries missing, rebuilding fresh"
    local fresh="${FB_MAGIC}
LOADING NONE"
    for module in $FB_MODULES; do
        fresh="${fresh}
M ${module} REBUILT f=0 o=0 last=NONE"
    done
    fb_write "${fresh}
END"
}

do_status() {
    find_misc || { echo "ERROR: misc not found"; return 1; }
    fb_check_magic || { echo "No valid fallback table"; return 1; }
    echo "=== Module Fallback Status ==="
    for module in $FB_MODULES; do
        echo "  $module: state=$(fb_get_state $module) fails=$(fb_get_field $module f=) oks=$(fb_get_field $module o=) last=$(fb_get_field $module last=)"
    done
    echo "  loading=$(fb_get_loading)"
}

do_clear() {
    find_misc && fb_check_magic || return 1
    local f="$(fb_get_field "$1" "f=")"
    local o="$(fb_get_field "$1" "o=")"
    fb_set_module "$1" "REBUILT" "${f:-0}" "${o:-0}" "NONE"
    echo "module_fallback: $1 re-enabled as REBUILT"
}

do_clear_all() {
    find_misc || return 1
    for module in $FB_MODULES; do
        fb_set_module "$module" "REBUILT" 0 0 "NONE"
    done
    echo "module_fallback: all reset to REBUILT"
}

case "$1" in
    boot) do_boot ;;
    verify) do_verify ;;
    --status) do_status ;;
    --clear) do_clear "$2" ;;
    --clear-all) do_clear_all ;;
    *) echo "Usage: module_fallback.sh {boot|verify|--status|--clear M|--clear-all}"; exit 1 ;;
esac
