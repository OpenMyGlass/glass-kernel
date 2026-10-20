#!/system/bin/sh
# OpenMyGlass CPU tuning profiles for Glass XE24 (OMAP4430), applied through sysfs.
#
#   omg-tune.sh stock|balanced|cool|status
#
# Nothing is persistent: a reboot returns to the kernel defaults ("stock"). Each
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
profile_values() {
    case "$1" in
        stock)    echo "1008000 1008000 99 90 20000 80000 20000 cfq" ;;
        balanced) echo "1008000 600000 90 85 40000 60000 20000 deadline" ;;
        cool)     echo "800000 600000 95 85 60000 60000 30000 deadline" ;;
        *)        return 1 ;;
    esac
}

put() {  # file value
    if [ ! -w "$1" ]; then
        echo "omg-tune: skipped $1 (missing or not writable)" >&2
        failed=1
        return
    fi
    echo "$2" > "$1" 2>/dev/null
    got=$(cat "$1" 2>/dev/null)
    case "$got" in
        "$2"|*"[$2]"*) ;;
        *) echo "omg-tune: $1 is '$got' after writing '$2'" >&2; failed=1 ;;
    esac
}

status() {
    for f in "$POLICY/scaling_governor" "$POLICY/scaling_cur_freq" "$POLICY/scaling_max_freq" \
             "$GOV/hispeed_freq" "$GOV/go_hispeed_load" "$GOV/target_loads" \
             "$GOV/above_hispeed_delay" "$GOV/min_sample_time" "$GOV/timer_rate" "$QUEUE/scheduler"; do
        [ -r "$f" ] && echo "${f##*/}: $(cat "$f")"
    done
    return 0
}

case "${1:-}" in
    status) status; exit 0 ;;
    stock|balanced|cool) ;;
    *) echo "usage: $0 stock|balanced|cool|status" >&2; exit 2 ;;
esac

# shellcheck disable=SC2046 # word splitting into the positional values is intended
set -- $(profile_values "$1")
put "$POLICY/scaling_max_freq" "$1"
if [ "$(cat "$POLICY/scaling_governor" 2>/dev/null)" = interactive ]; then
    put "$GOV/hispeed_freq" "$2"
    put "$GOV/go_hispeed_load" "$3"
    put "$GOV/target_loads" "$4"
    put "$GOV/above_hispeed_delay" "$5"
    put "$GOV/min_sample_time" "$6"
    put "$GOV/timer_rate" "$7"
else
    echo "omg-tune: governor is not interactive; left its tunables alone" >&2
fi
put "$QUEUE/scheduler" "$8"
exit "$failed"
