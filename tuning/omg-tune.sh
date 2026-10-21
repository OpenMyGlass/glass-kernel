#!/system/bin/sh
# OpenMyGlass CPU tuning profiles for Glass XE24 (OMAP4430), applied through sysfs.
#
#   omg-tune.sh stock|balanced|cool|status
#   omg-tune.sh input-boost on|off   (tuned kernels: boost to hispeed_freq on touchpad input)
#
# Nothing is persistent: a reboot returns to the defaults of the running kernel build
# and of the system's init scripts, which may set their own values (see docs/tuning.md). Each
# value is written only if its file exists and is read back; failures are reported
# and skipped, never fatal, because this runs at boot. Exit status: 0 all applied,
# 1 some values could not be applied, 2 usage error.
# See docs/tuning.md for the profiles and how to measure them.

SYS=${OMG_SYSFS:-/sys}
POLICY=$SYS/devices/system/cpu/cpu0/cpufreq
GOV=$SYS/devices/system/cpu/cpufreq/interactive
QUEUE=$SYS/block/mmcblk0/queue
failed=0

# profile: max hispeed go_hispeed_load target_loads above_hispeed_delay min_sample_time timer_rate scheduler
# A comma stands for a space inside one value (target_loads, above_hispeed_delay: "base freq:value").
# hispeed equals max in every profile: on Glass kernels hispeed_freq is also the governor's
# ceiling, and on kernels without patches/tuned/0009 a target above it drops the CPU to its
# lowest speed (docs/tuning.md).
profile_values() {
    case "$1" in
        stock)    echo "1008000 1008000 99 90 20000 80000 20000 cfq" ;;
        balanced) echo "1008000 1008000 99 90,800000:95 20000 60000 20000 deadline" ;;
        cool)     echo "800000 800000 99 90 20000 60000 30000 deadline" ;;
        *)        return 1 ;;
    esac
}

matches() {  # read-back expected
    # Kernel formats: target_loads ends with a space; schedulers show the active one in [].
    case "$1" in
        "$2"|"$2 "|*"[$2]"*) return 0 ;;
        *) return 1 ;;
    esac
}

write_value() {  # file value
    # OMG_TEST_FIRST_TOKEN_ONLY is test-only: it makes the write behave like a kernel that
    # parses just the first number. Unset on a device, so this is a plain write there.
    if [ -n "${OMG_TEST_FIRST_TOKEN_ONLY:-}" ]; then
        echo "${2%% *}" > "$1" 2>/dev/null
    else
        echo "$2" > "$1" 2>/dev/null
    fi
}

put() {  # file value
    if [ ! -w "$1" ]; then
        echo "omg-tune: skipped $1 (missing or not writable)" >&2
        failed=1
        return
    fi
    write_value "$1" "$2"
    got=$(cat "$1" 2>/dev/null)
    if ! matches "$got" "$2"; then
        # A kernel without per-frequency support parses only the first number: retry with it
        # and accept that, quietly, if it reads back.
        case "$2" in
            *" "*)
                first=${2%% *}
                write_value "$1" "$first"
                got=$(cat "$1" 2>/dev/null)
                matches "$got" "$first" && return
                ;;
        esac
        echo "omg-tune: $1 is '$got' after writing '$2'" >&2
        failed=1
    fi
}

status() {
    for f in "$POLICY/scaling_governor" "$POLICY/scaling_cur_freq" "$POLICY/scaling_max_freq" \
             "$GOV/hispeed_freq" "$GOV/go_hispeed_load" "$GOV/target_loads" \
             "$GOV/above_hispeed_delay" "$GOV/io_is_busy" "$GOV/input_boost" "$GOV/min_sample_time" "$GOV/timer_rate" "$QUEUE/scheduler"; do
        [ -r "$f" ] && echo "${f##*/}: $(cat "$f")"
    done
    return 0
}

# Keep hispeed_freq at or above scaling_max_freq at every step, so that no target is ever
# above it (see profile_values): a new hispeed_freq at or above the current scaling_max_freq
# is written before scaling_max_freq, a lower one after it.
# An unreadable maximum counts as higher, so hispeed_freq is then written last.
hispeed_before_max() {  # new_hispeed
    cur_max=$(cat "$POLICY/scaling_max_freq" 2>/dev/null)
    case "$cur_max" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge "$cur_max" ]
}

# hispeed_freq now reads at least new_max (unreadable: no).
hispeed_covers() {  # new_max
    cur_hispeed=$(cat "$GOV/hispeed_freq" 2>/dev/null)
    case "$cur_hispeed" in ''|*[!0-9]*) return 1 ;; esac
    [ "$cur_hispeed" -ge "$1" ]
}

# Commas to spaces, in the shell itself: Android 4.4's toolbox has no tr.
spaced() {  # value
    old_ifs=$IFS
    IFS=,
    set -f
    # shellcheck disable=SC2086 # splitting at the commas is intended
    set -- $1
    set +f
    IFS=$old_ifs
    echo "$*"
}

# Tests source the functions only.
[ -n "${OMG_LIB:-}" ] && return 0

usage() {
    echo "usage: $0 stock|balanced|cool|status" >&2
    echo "       $0 input-boost on|off" >&2
    exit 2
}

case "${1:-}" in
    status) status; exit 0 ;;
    input-boost)
        # Profiles leave input_boost alone; this sets it on its own. Kernels without it
        # (stock XE24, the stock build) report the file as missing and exit 1.
        [ $# -eq 2 ] || usage
        case "$2" in
            on) put "$GOV/input_boost" 1 ;;
            off) put "$GOV/input_boost" 0 ;;
            *) usage ;;
        esac
        exit "$failed" ;;
    stock|balanced|cool) ;;
    *) usage ;;
esac

# shellcheck disable=SC2046 # word splitting into the positional values is intended
set -- $(profile_values "$1")
interactive=no
[ "$(cat "$POLICY/scaling_governor" 2>/dev/null)" = interactive ] && interactive=yes
hispeed_first=no
[ "$interactive" = yes ] && hispeed_before_max "$2" && hispeed_first=yes
if [ "$hispeed_first" = yes ]; then
    put "$GOV/hispeed_freq" "$2"
    if hispeed_covers "$1"; then
        put "$POLICY/scaling_max_freq" "$1"
    else
        echo "omg-tune: left scaling_max_freq alone: hispeed_freq is below $1" >&2
        failed=1
    fi
else
    put "$POLICY/scaling_max_freq" "$1"
fi
if [ "$interactive" = yes ]; then
    if [ "$hispeed_first" = no ]; then
        if hispeed_before_max "$2"; then
            put "$GOV/hispeed_freq" "$2"
        else
            echo "omg-tune: left hispeed_freq alone: scaling_max_freq is above $2 or unreadable" >&2
            failed=1
        fi
    fi
    put "$GOV/go_hispeed_load" "$3"
    put "$GOV/target_loads" "$(spaced "$4")"
    put "$GOV/above_hispeed_delay" "$(spaced "$5")"
    put "$GOV/min_sample_time" "$6"
    put "$GOV/timer_rate" "$7"
else
    echo "omg-tune: governor is not interactive; left its tunables alone" >&2
fi
put "$QUEUE/scheduler" "$8"
exit "$failed"
