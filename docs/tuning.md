# Tuning: less heat, more battery

Nothing here has been measured on hardware yet. Every profile is reversible: a reboot returns to the kernel defaults.

## What stock XE24 already does

From the source (commit `989d925`):
- **CPU frequencies:** 300, 600, 800 and 1008 MHz. 1008 MHz is the "NITRO" point at 1.388 V.
- **Governor:** `interactive`. It jumps to the maximum frequency at 99% load (`go_hispeed_load`) and stays at least 80 ms (`min_sample_time`).
- **Thermal throttling** (`board-notle.c`, by PCB temperature):

| PCB temperature | Max frequency | Time at the top frequency |
|---|---|---|
| below 30 °C | 1008 MHz | 37% |
| below 35 °C | 1008 MHz | 24% |
| below 40 °C | 800 MHz | 19% |
| below 55 °C | 800 MHz | 14% |
| 55–85 °C | 600 MHz | 6% down to 1% |

- **Die limits:** alert at 100 °C, shutdown at 125 °C.

So above about 35 °C, which is normal when Glass is worn, the CPU is already limited to 800 MHz. Most of the heat comes from bursts when the device is cool, and from the display, camera and radio, which the kernel does not control.

## Runtime profiles (`tuning/omg-tune.sh`)

| Value | stock | balanced | cool |
|---|---|---|---|
| `scaling_max_freq` (kHz) | 1008000 | 1008000 | 800000 |
| `hispeed_freq` (kHz) | 1008000 | 600000 | 600000 |
| `go_hispeed_load` (%) | 99 | 90 | 95 |
| `target_loads` (%) | 90 | 85 | 85 |
| `above_hispeed_delay` (µs) | 20000 | 40000 | 60000 |
| `min_sample_time` (µs) | 80000 | 60000 | 60000 |
| `timer_rate` (µs) | 20000 | 20000 | 30000 |
| eMMC I/O scheduler | cfq | deadline | deadline |

- **balanced** keeps bursts up to 1008 MHz, but goes to 600 MHz first instead of straight to the maximum.
- **cool** never uses the 1.388 V NITRO point. It mostly differs from stock when Glass is cool, for example right after waking up.

To try one over adb (needs root; see glass-rom):

```sh
adb push tuning/omg-tune.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/omg-tune.sh cool'
adb shell su -c 'sh /data/local/tmp/omg-tune.sh status'
```

## The `tuned` build

`VARIANT=tuned scripts/build-in-container.sh`, built by CI as the `kernel-tuned` artifact. It differs from stock only in `configs/tuned.config`:
- the default I/O scheduler is deadline;
- two debug-only statistics are off.

`PM_DEBUG` stays on, because OMAP's off-mode switches live under it.

## Deliberately not done
- **Undervolting:** SmartReflex 1.5 already trims voltages, and OMAP4 kernels that undervolted saw random reboots for little gain.
- **Overclocking, or enabling the 1.2 GHz point:** more heat, the opposite of the goal.
- **Capping the GPU:** its frequency policy is in the out-of-tree PowerVR module.
- **Stricter thermal thresholds** (`board-notle.c` patch): a candidate once there are measurements.

## Measurement plan (on hardware)

For each profile, starting at full charge and room temperature, run three 30-minute scenarios:
1. idle with the screen off;
2. turn-by-turn navigation from OpenMyGlass with the screen on;
3. video recording.

Record, every 30 s, over adb:
- **battery:** `cat /sys/class/power_supply/*/capacity` and `current_now` where available;
- **temperature:** `cat /sys/class/thermal/thermal_zone*/temp`, plus the PCB sensor under `/sys/devices/platform/` (see `notle_pcb_sensor.c`);
- **frequency residency:** `cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state`, read at the start and the end;
- **smoothness:** dropped frames in navigation card updates and recording (`dumpsys gfxinfo` where available).

A profile becomes the default only if it lowers drain or temperature without visible stutter. Results go in an issue, with the raw logs attached.
