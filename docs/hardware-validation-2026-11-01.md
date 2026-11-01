<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Hardware validation — 2026-11-01

First validation on a real Google Glass Explorer Edition (XE24, serial redacted). Kernels were run with `fastboot boot` only (RAM, nothing written to the device); a reboot returns to the stock firmware. Full root for the privileged reads came from an init-started helper (owner's test rig), SELinux permissive.

## Results

- **Phase 1/2 — tuned build boots.** `Linux version 3.4.94-g989d925-dirty`, reproducible build (Linaro gcc 4.7.3). `interactive` governor; `deadline` I/O scheduler active; `io_is_busy=1`, `input_boost=1` present.
- **Phase 3 — GPU module from source loads clean.** `/proc/modules` lists `pvrsrvkm_sgx540_120 ... Live (O)` (our build, size 339136, vs the stock 447058). `dmesg` shows `PVR: PVRSRVDriverProbe(...)` and **no** `SGXInit` build-options or DDK-version mismatch. SurfaceFlinger runs and the display renders (GLASS logo captured). So the DDK `1.9@2166536` module built here is binary-compatible with the tuned kernel on real hardware.
- **Phase 6 — input boost fires on touchpad input.** With `input_boost=1`, injected touchpad events (`sendevent /dev/input/event3`) produced `cpufreq_interactive_boost: input` ftrace lines; with `input_boost=0`, none. The governor's input handler connected to `sensor00fn11` (`cpufreq_interactive_input_connect`).
- **hispeed_freq clamp (patches/tuned/0009).** With the `cool` profile (hispeed = max = 800 MHz) under a two-core load, `scaling_cur_freq` held at 800000 and never fell to 300000 (the stock drop-to-lowest behaviour).
- **omg-tune profiles.** `stock` -> 1008000 / cfq; `cool` -> 800000 / deadline; `eco` -> 600000 / deadline; back to `stock`. Each sets `hispeed_freq`, `scaling_max_freq` and the scheduler as specified.
- **Phase 5 — tuned-stable (3.4.113) boots.** `Linux version 3.4.113-gb6ea856-dirty`. Its GPU module (built for the stable merge) loads `Live` with no SGXInit mismatch; SurfaceFlinger runs; `input_boost`/`io_is_busy`/`deadline` present. (One follow-up: inspect the exact `dmesg` mmc/ext4 lines, hardware-checks tuned-stable step 7.)

## Still open (need the full ROM or more build infrastructure)

- A flashable OpenMyGlass system image (with the owner's vendor blobs) to exercise the AOSP HALs on device — not built here.
- Input-boost firing from a real finger swipe (only synthetic injection was used), the full tuned-stable boot checklist, and battery measurements beyond a short off-charger drain.
