#!/bin/sh
# Tests for tuning/omg-tune.sh against a fake sysfs tree.
set -u
here=$(cd "$(dirname "$0")" && pwd)
tune="$here/../tuning/omg-tune.sh"
fail=0

setup() {
    root=$(mktemp -d)
    gov="$root/sys/devices/system/cpu/cpufreq/interactive"
    pol="$root/sys/devices/system/cpu/cpu0/cpufreq"
    q="$root/sys/block/mmcblk0/queue"
    mkdir -p "$gov" "$pol" "$q"
    echo 1008000 > "$pol/scaling_max_freq"
    echo interactive > "$pol/scaling_governor"
    for kv in hispeed_freq=1008000 go_hispeed_load=99 target_loads=90 above_hispeed_delay=20000 \
              min_sample_time=80000 timer_rate=20000; do
        echo "${kv#*=}" > "$gov/${kv%%=*}"
    done
    echo "90 " > "$gov/target_loads"
    echo "noop deadline [cfq] " > "$q/scheduler"
}
val() { cat "$root/sys/$1"; }
check() {  # name expected actual
    if [ "$2" != "$3" ]; then echo "FAIL: $1: expected '$2', got '$3'"; fail=1; fi
}
run() { OMG_SYSFS="$root/sys" sh "$tune" "$@"; }

# Read-back comparison, with the kernel's formats: target_loads prints a trailing space,
# the scheduler file lists every scheduler with the active one in brackets.
lib() { OMG_LIB=1 sh -c '. "$0" && "$@"' "$tune" "$@"; }
lib matches "85 " 85 || { echo "FAIL: '85 ' should match 85"; fail=1; }
lib matches "noop [deadline] cfq " deadline || { echo "FAIL: bracketed scheduler should match"; fail=1; }
lib matches "8 " 85 && { echo "FAIL: '8 ' should not match 85"; fail=1; }
lib matches "noop deadline [cfq] " deadline && { echo "FAIL: inactive scheduler should not match"; fail=1; }

setup
run cool >/dev/null 2>&1; check "cool exit" 0 $?
check "cool max" 800000 "$(val devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
check "cool hispeed" 600000 "$(val devices/system/cpu/cpufreq/interactive/hispeed_freq)"
check "cool go_hispeed_load" 95 "$(val devices/system/cpu/cpufreq/interactive/go_hispeed_load)"
check "cool above_hispeed_delay" 60000 "$(val devices/system/cpu/cpufreq/interactive/above_hispeed_delay)"
check "cool timer_rate" 30000 "$(val devices/system/cpu/cpufreq/interactive/timer_rate)"
check "cool scheduler" deadline "$(val block/mmcblk0/queue/scheduler)"

run stock >/dev/null 2>&1
check "stock max" 1008000 "$(val devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
check "stock go_hispeed_load" 99 "$(val devices/system/cpu/cpufreq/interactive/go_hispeed_load)"
check "stock min_sample_time" 80000 "$(val devices/system/cpu/cpufreq/interactive/min_sample_time)"
check "stock scheduler" cfq "$(val block/mmcblk0/queue/scheduler)"

run balanced >/dev/null 2>&1
check "balanced max" 1008000 "$(val devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
check "balanced hispeed" 600000 "$(val devices/system/cpu/cpufreq/interactive/hispeed_freq)"
check "balanced target_loads" 85 "$(val devices/system/cpu/cpufreq/interactive/target_loads)"
rm -rf "$root"

# Missing tunables are skipped, the rest is still applied, and the exit status reports it.
setup
rm "$gov/timer_rate"
out=$(run cool 2>&1); status=$?
check "missing file status" 1 "$status"
case "$out" in *timer_rate*) ;; *) echo "FAIL: missing file not reported"; fail=1 ;; esac
check "others still applied" 800000 "$(val devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
rm -rf "$root"

# Interactive tunables are only touched while interactive is the governor.
setup
echo ondemand > "$pol/scaling_governor"
run cool >/dev/null 2>&1
check "other governor untouched" 99 "$(val devices/system/cpu/cpufreq/interactive/go_hispeed_load)"
check "max still capped" 800000 "$(val devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
rm -rf "$root"

# Unknown profile is refused and changes nothing.
setup
run turbo >/dev/null 2>&1; check "unknown exit" 2 $?
check "unknown untouched" 1008000 "$(val devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
out=$(run status 2>&1)
case "$out" in *"scaling_max_freq: 1008000"*) ;; *) echo "FAIL: status output: $out"; fail=1 ;; esac
rm -rf "$root"

[ "$fail" -eq 0 ] && echo "omg-tune: all tests passed"
exit "$fail"
