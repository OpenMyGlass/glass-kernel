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
check "cool above_hispeed_delay" "60000 800000:80000" "$(val devices/system/cpu/cpufreq/interactive/above_hispeed_delay)"
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
check "balanced above_hispeed_delay" "40000 800000:60000" "$(val devices/system/cpu/cpufreq/interactive/above_hispeed_delay)"
rm -rf "$root"

# A kernel that parses only the first number reads back a single value: that is accepted
# quietly (exit 0, nothing printed). OMG_TEST_FIRST_TOKEN_ONLY is the script's test-only hook
# that makes the write behave like such a kernel.
test_fallback_single_delay() {
    setup
    out=$(OMG_TEST_FIRST_TOKEN_ONLY=1 run balanced 2>&1); status=$?
    check "fallback exit" 0 "$status"
    check "fallback output" "" "$out"
    check "fallback delay" 40000 "$(val devices/system/cpu/cpufreq/interactive/above_hispeed_delay)"
    rm -rf "$root"
    # If even the single value does not read back, it is still a failure.
    setup
    chmod a-w "$gov/above_hispeed_delay"
    out=$(run balanced 2>&1); status=$?
    if [ "$(id -u)" -ne 0 ]; then
        check "unwritable delay exit" 1 "$status"
        case "$out" in *above_hispeed_delay*) ;; *) echo "FAIL: unwritable delay not reported"; fail=1 ;; esac
    fi
    rm -rf "$root"
    setup
    rm "$gov/above_hispeed_delay"
    ln -s /dev/null "$gov/above_hispeed_delay"
    out=$(run balanced 2>&1); status=$?
    check "unreadable-back delay exit" 1 "$status"
    case "$out" in *above_hispeed_delay*) ;; *) echo "FAIL: delay mismatch not reported"; fail=1 ;; esac
    rm -rf "$root"
}
test_fallback_single_delay

# status lists io_is_busy and above_hispeed_delay when present, and says nothing of io_is_busy otherwise.
setup
echo 0 > "$gov/io_is_busy"
out=$(run status 2>&1)
case "$out" in *"io_is_busy: 0"*) ;; *) echo "FAIL: status lacks io_is_busy: $out"; fail=1 ;; esac
case "$out" in *"above_hispeed_delay: 20000"*) ;; *) echo "FAIL: status lacks above_hispeed_delay: $out"; fail=1 ;; esac
rm "$gov/io_is_busy"
out=$(run status 2>&1)
case "$out" in *io_is_busy*) echo "FAIL: status mentions missing io_is_busy"; fail=1 ;; esac
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
