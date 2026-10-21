# Tuning: less heat, more battery

Nothing here has been measured on hardware yet. Every profile is reversible: a reboot returns to the defaults of the running kernel build (on the `tuned` build that includes the deadline scheduler) and of the system's init scripts.

`stock` writes the **kernel's** defaults. Android 4.4's init scripts or power HAL may set their own values at boot or on screen on/off, and could also overwrite a profile. The first step on hardware is to check this (see the measurement plan).

## What stock XE24 already does

From the source (commit `989d925`):
- **CPU frequencies:** 300, 600, 800 and 1008 MHz. 1008 MHz is the "NITRO" point at 1.388 V.
- **Governor:** `interactive`. It jumps to the maximum frequency at 99% load (`go_hispeed_load`) and stays at least 80 ms (`min_sample_time`).
- **Thermal throttling** (`board-notle.c`, by PCB temperature):

| PCB temperature | Top / cooling frequency | Time at the top frequency per 20 s cycle |
|---|---|---|
| below 30 °C | 1008 / 800 MHz | 37% |
| below 35 °C | 1008 / 800 MHz | 24% |
| below 40 °C | 800 / 600 MHz | 19% |
| below 55 °C | 800 / 600 MHz | 14% |
| 55 °C and above | 600 / 300 MHz | 6%, 3%, 2%, then 1% from 80 °C |

- **Turbo sprint:** a separate table allows 1008 MHz without duty-cycling up to 65 °C, for at most 10 s, when `turbo_sprint` is set through sysfs.
- **Die limits** (ES2 and later silicon): monitoring from 85 °C, alert at 100 °C, critical at 110 °C, shutdown at 125 °C. ES1.0 uses 105 °C alert and 120 °C shutdown.

So above about 35 °C, which is normal when Glass is worn, the CPU is already limited to 800 MHz and spends 81–86% of each cycle at 600 MHz. Most of the heat comes from bursts when the device is cool, and from the display, camera and radio, which the kernel does not control.

## Runtime profiles (`tuning/omg-tune.sh`)

| Value | stock | balanced | cool |
|---|---|---|---|
| `scaling_max_freq` (kHz) | 1008000 | 1008000 | 800000 |
| `hispeed_freq` (kHz) | 1008000 | 600000 | 600000 |
| `go_hispeed_load` (%) | 99 | 90 | 95 |
| `target_loads` (%) | 90 | 85 | 85 |
| `above_hispeed_delay` (µs) | 20000 | `40000 800000:60000` | `60000 800000:80000` |
| `min_sample_time` (µs) | 80000 | 60000 | 60000 |
| `timer_rate` (µs) | 20000 | 20000 | 30000 |
| eMMC I/O scheduler | cfq | deadline | deadline |

- **balanced** keeps bursts up to 1008 MHz, but goes to 600 MHz first instead of straight to the maximum.
- `above_hispeed_delay` takes a per-frequency list on the `tuned` build (see the backports below): the first value applies below 800 MHz, the second at 800 MHz and above. On a kernel without per-frequency support, the profile writes only the first value.
- The profiles do not set `io_is_busy`; `status` shows it when present.
- **cool** never uses the 1.388 V NITRO point. It mostly differs from stock when Glass is cool, for example right after waking up.

To try one over adb (needs root adb, from glass-rom's insecure boot image):

```sh
adb root
adb push tuning/omg-tune.sh /data/local/tmp/
adb shell sh /data/local/tmp/omg-tune.sh cool
adb shell sh /data/local/tmp/omg-tune.sh status
```

## The `tuned` build

`VARIANT=tuned scripts/build-in-container.sh`, built by CI as the `kernel-tuned` artifact. It differs from stock in `configs/tuned.config` and in the patches under `patches/tuned/`, which only this variant applies:
- the default I/O scheduler is deadline;
- two debug-only statistics are off;
- the debugging and tracing options below, which cost time at runtime, are off;
- the interactive governor has two later AOSP features, backported with their upstream follow-up fixes (see below).

| Option off | Runtime cost in stock |
|---|---|
| `DEBUG_SPINLOCK` | checks owner and magic on every spinlock lock and unlock, and makes `spinlock_t` larger |
| `DEBUG_MUTEXES` | checks every mutex lock and unlock, and disables mutex spinning (`MUTEX_SPIN_ON_OWNER` comes back on) |
| `DEBUG_RT_MUTEXES` | checks every rt-mutex operation (futex priority inheritance, used by Android) |
| `DEBUG_PI_LIST` | walks and checks the priority list on every rt-mutex enqueue and dequeue |
| `IRQSOFF_TRACER` | hooks every interrupt disable and enable (`TRACE_IRQFLAGS`), even when not tracing |
| `FUNCTION_TRACER` | builds the kernel with `-pg`: an mcount call in every function prologue |
| `FUNCTION_GRAPH_TRACER` | depends on `FUNCTION_TRACER`; adds return hooks |
| `FUNCTION_PROFILER` | depends on `FUNCTION_TRACER`; per-function hit counters |
| `PERSISTENT_TRACER` | Android's last-function-before-reset tracer; it selects `FUNCTION_TRACER`, so it has to go too. Notle registers no device for it, so it is unused in stock |
| `SCHEDSTATS` | updates scheduler statistics on every enqueue, dequeue and context switch |
| `TIMER_STATS` | records the caller of every timer start (`/proc/timer_stats`) |
| `KPROBES` | keeps the kprobe hooks in the exception and fault paths; nothing on Glass sets probes |
| `OPROFILE` | profiler driver and its hooks; Android uses `perf` events, which stay |

Side effects Kconfig resolves on its own: `MUTEX_SPIN_ON_OWNER` turns on (it needs `DEBUG_MUTEXES` off), `SPLIT_PTLOCK_CPUS` goes from 999999 to 4 (split page-table locks need `DEBUG_SPINLOCK` off), and `KRETPROBES` and `KPROBE_EVENT` go with `KPROBES`. With no function tracer left, nothing selects `TRACING` any more, so the fragment turns on `ENABLE_DEFAULT_TRACERS` and checks that `EVENT_TRACING` and `TRACEPOINTS` stay on.

Debug options that stay on:
- `PM_DEBUG`, because OMAP's off-mode switches live under it;
- `DEBUG_FS`, because power and thermal tools read it;
- `FTRACE`, `TRACEPOINTS` and `EVENT_TRACING`, because Android's `atrace` and `systrace` use event tracing, which costs nothing while it is off;
- `DEBUG_KERNEL` and `KALLSYMS`, which only gate other options and give readable oopses.

### Interactive governor backports (`patches/tuned/`)

- `0001`–`0004`: AOSP `kernel/common` android-3.4 (now `deprecated/android-3.4`) commits e43dde3b (per-frequency `above_hispeed_delay`), fbcad723 (`io_is_busy`), and their upstream fixes cad16844 (crash on a malformed write) and 2e745d35 (uninitialised spinlock).
- `0005` (OpenMyGlass): `io_is_busy` defaults to 1.

The two new knobs, under `/sys/devices/system/cpu/cpufreq/interactive/`:
- `above_hispeed_delay` takes either one delay `D` or a list `D F:D …`, with the same syntax as `target_loads`. For example, `20000 1008000:80000` waits 20 ms above `hispeed_freq` and 80 ms at 1008 MHz and above. Stock XE24 kernels take only the single value.
- `io_is_busy` (0 or 1). On this 3.4 kernel, `get_cpu_idle_time_us` leaves iowait out, so the stock governor counts iowait as busy. The tuned default `io_is_busy=1` matches stock. `0` counts iowait as idle (the upstream default); it is an option to measure, and may ramp up less during eMMC-heavy work.

`above_hispeed_delay` and `target_loads` read back with a trailing space (`20000 `). The kernel rejects that string, so trim it before writing a saved value back.

Size, from the CI artifacts of run 39650912927 (before the patches): the `tuned` `zImage` is 4,839,160 bytes, against 5,075,816 for `stock` (236,656 bytes, 4.7%, smaller).

## Deliberately not done
- **Undervolting:** SmartReflex 1.5 already trims voltages, and OMAP4 kernels that undervolted saw random reboots for little gain.
- **Overclocking, or enabling the 1.2 GHz point:** more heat, the opposite of the goal.
- **Capping the GPU:** its frequency policy is in the out-of-tree PowerVR module.
- **Stricter thermal thresholds** (`board-notle.c` patch): a candidate once there are measurements.

## Measurement plan (on hardware)

First, on a freshly booted device, run `omg-tune.sh status` before applying anything, then again after a screen off/on cycle. If the values differ from the kernel defaults above, the system sets its own: record them, and decide whether `stock` should restore those instead.

Then, for each profile, starting at full charge and room temperature, run three 30-minute scenarios:
1. idle with the screen off;
2. turn-by-turn navigation from OpenMyGlass with the screen on;
3. video recording.

One more axis separates the config effect from the profile effect: the `stock` build against the `tuned` build, each with the `stock` profile, in the same three scenarios. Later, optionally, `io_is_busy` 1 against 0 on the `tuned` build.

Record, every 30 s, over adb:
- **battery:** `cat /sys/class/power_supply/*/capacity` and `current_now` where available;
- **temperature:** `cat /sys/class/thermal/thermal_zone*/temp`, plus the PCB sensor under `/sys/devices/platform/` (see `notle_pcb_sensor.c`);
- **frequency residency:** `cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state`, read at the start and the end;
- **smoothness:** dropped frames in navigation card updates and recording (`dumpsys gfxinfo` where available).

A profile becomes the default only if it lowers drain or temperature without visible stutter. Results go in an issue, with the raw logs attached.
