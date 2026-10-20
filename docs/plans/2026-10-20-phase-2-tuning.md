# Phase 2: Less heat, more battery — Plan

**Goal:** Prepare the tuning that can be done without hardware, in two separate, reversible parts. Nothing is tested on a device in this phase; the measurement plan is part of the deliverable.

1. **Runtime profiles** (`tuning/omg-tune.sh`): writes cpufreq/interactive/I/O scheduler values through sysfs.
   - `stock` restores the kernel's defaults, `balanced` changes ramp behaviour only, `cool` also caps the CPU at 800 MHz.
   - `status` prints the current values.
   - It never edits the kernel, so a reboot always returns to stock. glass-rom will install it later.
2. **A `tuned` build variant** (config fragment `configs/tuned.config`): build-only options that are safe on their own.
   - The default I/O scheduler is deadline.
   - Two debug-only options are dropped (`THERMAL_FRAMEWORK_DEBUG`, `CPU_FREQ_STAT_DETAILS`).
   - `PM_DEBUG` stays, because OMAP's off-mode switches live under it.
   - CI builds both `stock` and `tuned`.

## Facts from the source (commit 989d925)
- **MPU OPPs:** 300/600/800/1008 MHz (1008 = NITRO, 1.388 V). 1200 MHz is only for "perf silicon".
- **SGX540:** 153.6/307.2 MHz.
- **Interactive governor defaults:**
  - `go_hispeed_load` 99, `target_loads` 90;
  - `min_sample_time` 80 ms, `timer_rate` 20 ms, `above_hispeed_delay` 20 ms;
  - `hispeed_freq` 0, which means the policy max.
- **Thermal:** the board's duty-cycle governor already throttles by PCB temperature: max 800 MHz from 35 °C, 600 MHz from 55 °C. Die alert is at 100 °C, shutdown at 125 °C.

## Profiles
| Value | stock | balanced | cool |
|---|---|---|---|
| `scaling_max_freq` | 1008000 | 1008000 | 800000 |
| `hispeed_freq` | 1008000 | 600000 | 600000 |
| `go_hispeed_load` | 99 | 90 | 95 |
| `target_loads` | 90 | 85 | 85 |
| `above_hispeed_delay` | 20000 | 40000 | 60000 |
| `min_sample_time` | 80000 | 60000 | 60000 |
| `timer_rate` | 20000 | 20000 | 30000 |
| eMMC scheduler | cfq | deadline | deadline |

Rationale:
- `cool` avoids the 1.388 V NITRO OPP entirely. Above 35 °C stock is already capped at 800 MHz, so in practice `cool` differs only when the device is cool.
- `balanced` keeps bursts to 1008 MHz but stops jumping straight to the maximum.

## Deliberately not done (risk)
- Undervolting or OPP voltage edits: SmartReflex 1.5 already trims the voltage, and the OMAP4 community reports random reboots for little gain.
- Overclocking, or enabling 1200 MHz.
- Capping the GPU: its DVFS lives in the out-of-tree PVR module.
- Stricter duty-cycle thresholds in `board-notle.c`: a candidate patch once there are measurements.

## Tasks
1. `tuning/omg-tune.sh` plus `tests/test_omg_tune.sh` (fake sysfs tree). It writes only to files that exist and reads each value back. A missing or unwritable file is reported and skipped, never fatal, because the script will run at boot. Unknown profiles are refused.
2. `configs/tuned.config` and `VARIANT=stock|tuned` in `build.sh`. The fragment is applied with `scripts/config` and `oldconfig`, then each line is verified in `.config`; the build fails if Kconfig dropped one. CI builds both variants.
3. `docs/tuning.md`: profiles, how to apply them over adb, and the measurement plan for real hardware (battery drain per hour at idle/navigation/video, PCB temperature via the thermal sysfs, time spent per frequency from `cpufreq/stats/time_in_state`).
