# Phase 6: Touchpad input boost in the tuned builds — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `tuned` and `tuned-stable`, a swipe or tap on the Glass touchpad raises the CPU to `hispeed_freq` on its first input report, instead of waiting up to one timer sample (20 ms) for the governor to see the load. A sysfs knob turns it off. `stock` stays exactly Google's source and config.

**Architecture:**
- The interactive governor in Glass's own history had an input handler: AOSP added it in April 2012 and removed it in July 2012 ("now handled in userspace Power HAL instead"), before `glass-omap-xrx13b`. It is brought back as a patch under `patches/tuned/`, with the original author and message.
- The handler matches input devices by capability, kicks `cpufreq_interactive_boost()` on each `SYN_REPORT`, and is registered while the governor runs. Knob: `/sys/devices/system/cpu/cpufreq/interactive/input_boost`.
- A second, OpenMyGlass, patch turns it on by default, in the same way as `0005` does for `io_is_busy`.
- `tuning/omg-tune.sh` shows the knob in `status` and gets an `input-boost on|off` command. Profiles do not set it.

**Tech stack:** `git apply` patches, POSIX sh, GitHub Actions. Builds run in CI only: there is no docker on the owner's Mac.

**Spec:** glass-rom roadmap, phase R2; `reports/Ottimizzazioni kernel OMAP4.md` rates "the xrr02 interactive input handler" as low risk ("the match table must be extended to the touchpad"); phase 4 left it out.

## Global constraints

- Kernel code and patches are GPL-2.0-only. The backported patch keeps the original author's `From:`, date and message, and adds `(cherry picked from commit <sha> in AOSP kernel/common <branch>)`. Adapted hunks are noted in the message.
- `VARIANT=stock` is byte-identical: `zImage` `5b744fef8f8688562e19b8311225f324037aad49901ed78ee6854529de15caa1`, `.ko` `1ec003f32c94512564404bd80b9802f8715d1995df017c5bfae9b99c0cc991c8`.
- Safety: the boost goes only to `hispeed_freq`. Whatever `hispeed_freq` is set to, `omap_target()` picks the frequency with `cpufreq_frequency_table_target()`, which only considers table entries within `scaling_min_freq`–`scaling_max_freq`, and `omap_cpufreq_scale()` then clamps to the thermal limit (`max_thermal`). The table holds the enabled OPPs only (300–1008 MHz; 1.2 GHz is disabled). So no frequency above the 1008 MHz OPP, and no frequency, voltage or thermal limit that the governor could not already select. No OPP, voltage or thermal table changes.
- Builds stay reproducible (the repro workflow); every variant still builds `pvrsrvkm_sgx540_120.ko`. CRC changes against the previous `tuned` module are reported with `scripts/compare_ko.py`.
- No Google file, and nothing extracted from one, in the repo or CI. Device checks are written and marked NOT RUN.
- English. Shell passes `shellcheck -s sh`.

## Findings that shape the patch

- **Upstream commits** (AOSP `kernel/common`, verified on android.googlesource.com and as ancestors of the branches):
  - `7820a652885153a6f7062df100914adeccab9eef` "cpufreq: interactive: Boost frequency on touchscreen input" (Todd Poynor, 2012-04-02), on `android-3.4`. It is also in Glass's `glass-omap-xrx13b` history. The `android-3.0` copy is `2e21b68cd68be556224aee775f67fbbb5d6870a6`.
  - Later AOSP changes to the same code, also in Glass's history: `9fb153153b50` (shared `cpufreq_interactive_boost()`), `2e739a07915b` (trace event with a string, `"input"`), `a9a7eb003735` (own `cfinteractive` workqueue, `flush_work()` on stop).
  - Removal: `4e27eb56e819745a1b184f278d7f3dd3887a456c` "cpufreq: interactive: remove input_boost handling" on `android-3.4`; in Glass's tree as TI's copy `a021a1c1f680`.
  - The handler is taken in the form it had just before that removal, so it fits the current file (`cpufreq_interactive_boost()` and the string trace event already exist). The broodplank xrr02 tree has the same handler and match table: nothing TI-specific to take from it.
- **Glass's touchpad:** a Synaptics TM2240 on I2C bus 3 (`rmi_i2c` at 0x20, `board-notle.c`), driven by RMI4 F11 (`drivers/input/rmi4/rmi_f11.c`), input device name `sensor00fn11`. Capabilities: `EV_SYN`, `EV_ABS` with `ABS_MT_POSITION_X/Y`, `ABS_MT_PRESSURE`, `ABS_MT_TOUCH_MAJOR/MINOR`, `ABS_MT_ORIENTATION`, `ABS_MT_TRACKING_ID`, `ABS_MT_TOOL_TYPE` (protocol A, `type_a = 1`), `EV_SW`/`SW_CAMERA_LENS_COVER`, `INPUT_PROP_DIRECT`. No `EV_KEY`, no `BTN_TOUCH`, no `ABS_X`/`ABS_Y`. `rel_report_enabled = 0`, so the `rmi_mouse` device is not created.
  - So upstream's "touchpad" entry (`BTN_TOUCH` + `ABS_X/Y`, a single-touch touchpad) does **not** match Glass, but the "multi-touch touchscreen" entry (`EV_ABS` + `ABS_MT_POSITION_X/Y`) does. The match table needs no new entry; the commit message and docs say why.
  - Other input devices built for notle do not match: `ltr506_als`/`ltr506_ps` use `ABS_MISC`/`ABS_DISTANCE`, gpio-keys and the TWL6030 power button use keys, the MPU-9150 is an IIO device. A USB/Bluetooth HID or uinput device with MT axes would match too.
- **Duration:** each report sets every online CPU's floor to `hispeed_freq` (`cpufreq_interactive_boost()`), so the speed stays at or above `hispeed_freq` for `min_sample_time` after the **last** report (80 ms kernel default; 60 ms in `balanced` and `cool`), then drops by load. It does not set `boostpulse_endtime`, so `boostpulse_duration` does not apply. A continuous swipe keeps it up; nothing holds it after the finger lifts.
- **Hispeed under each profile:** kernel default `hispeed_freq` = policy max = 1008 MHz (and the `stock` profile writes 1008000), so on the kernel defaults a touch goes to 1008 MHz when the thermal table allows it; `balanced` and `cool` set 600 MHz.
- `cpufreq_interactive.c`, `governors.txt` and `include/linux/input.h` are byte-identical between the `tuned` source (989d925) and the `tuned-stable` merge (b6ea856), so the patches apply to both.

## Review focus

1. The boost can never exceed `hispeed_freq`, and the frequency actually set can never exceed `scaling_max_freq` or the thermal limit (check `cpufreq_interactive_boost()`, the speed-change task, `omap_target()`/`omap_cpufreq_scale()`).
2. The input handler is registered and unregistered under `gov_lock` together with the sysfs group; `flush_work()` runs before the last `GOV_STOP` unregisters it; the `event` callback runs in atomic context, so `cpufreq_interactive_boost()` must take only spinlocks.
3. A patch meant for `tuned` never touches `stock` (stock hashes, Task 2).
4. `omg-tune.sh` profiles do not change `input_boost`; `status` lists it only when present; `input-boost` on a kernel without the knob exits 1 with a message and writes nothing.

---

### Task 1: The patches

**Files:**
- Create: `patches/tuned/0006-cpufreq-interactive-Boost-frequency-on-touchscreen-i.patch`
- Create: `patches/tuned/0007-cpufreq-interactive-default-input_boost-to-1.patch`

- [ ] **Step 1:** In a checkout of `989d925` with `0001`–`0005` applied (`git am`), add the input handler as it was before `a021a1c1`: `#include <linux/input.h>`, `input_boost_val`, `inputopen`/`inputopen_wq`, `cpufreq_interactive_input_event/open/connect/disconnect`, the id table, `input_boost` attribute, `input_register_handler()` in the first `GOV_START`, `flush_work()` and `input_unregister_handler()` in `GOV_STOP`, workqueue creation in init and destruction in exit; `governors.txt` entry. `strict_strtoul` becomes `kstrtoul`, like the neighbouring attributes. Commit with `GIT_AUTHOR_*` = Todd Poynor, 2012-04-02 17:17:14 -0700, the original message, the cherry-pick line and an `[OpenMyGlass: …]` note.
- [ ] **Step 2:** Second commit, author OpenMyGlass: `input_boost_val = 1`, `governors.txt` "Default is 1" plus the duration. Message explains the Glass match, the duration and the safety bound.
- [ ] **Step 3:** `git format-patch --zero-commit --no-signature`, rename to `0006-`/`0007-`, copy to `patches/tuned/`.
- [ ] **Step 4:** Check they apply after `0001`–`0005` on both pinned sources with `git apply --check` (the files are identical, checked by blob hash).
- [ ] **Step 5:** Commit: `Bring back the interactive governor's input boost for the touchpad`.

### Task 2: CI build and hashes

- [ ] **Step 1:** Push branch `input-boost`, open the PR. Expected: build workflow green for the three variants; the `tuned` logs show `applying patches/tuned/0006-…` and `0007-…`; the `repro` workflow reports `identical` for all three.
- [ ] **Step 2:** From the `stock` log's SHA256SUMS: `zImage` and `.ko` equal the hashes above. Any difference stops the PR.
- [ ] **Step 3:** Download the `kernel-tuned` and `kernel-tuned-stable` artifacts and the main-branch ones (run 39671222156), run `scripts/compare_ko.py old.ko new.ko` for each pair, and record imported symbols and CRC differences. Expected: none, or only `module_layout` if `struct module` layout moves (it should not: the patch adds no exported symbol and changes no struct used by the module).
- [ ] **Step 4:** Record the new `tuned` and `tuned-stable` hashes and sizes in `docs/tuning.md`.

### Task 3: `omg-tune.sh`

**Files:**
- Modify: `tuning/omg-tune.sh`
- Modify: `tests/test_omg_tune.sh`

- [ ] **Step 1: Failing tests,** in the existing style:
  - `status` prints `input_boost: 1` when the file exists, and does not mention `input_boost` when it is missing.
  - `input-boost off` writes `0`, `input-boost on` writes `1`, exit 0, no output.
  - `input-boost off` with no `input_boost` file: exit 1, message names `input_boost`, nothing created.
  - `input-boost` with a bad or missing argument: exit 2, file unchanged.
  - The profiles leave `input_boost` alone (`cool` on a fake tree with `input_boost` = 1 keeps 1).
- [ ] **Step 2:** `sh tests/test_omg_tune.sh`. Expected: FAIL.
- [ ] **Step 3: Implement:** `input_boost` in the `status` list; `input-boost on|off` uses `put` (so it is read back, and a missing file is reported with exit 1); usage line updated.
- [ ] **Step 4:** `sh tests/test_omg_tune.sh` and `shellcheck -s sh tuning/omg-tune.sh tests/test_omg_tune.sh`. Expected: PASS, no output.
- [ ] **Step 5:** Commit: `omg-tune: show and set the touchpad input boost`.

### Task 4: Docs

**Files:**
- Modify: `docs/tuning.md` (backports section, knob, duration, measurement plan), `docs/hardware-checks.md` (NOT RUN checks), `README.md` (Status)

- [ ] **Step 1:** `docs/tuning.md`: `0006`/`0007` with SHAs; the knob, its default (1 on `tuned`/`tuned-stable`; absent on `stock`), duration (`min_sample_time` after the last report), the Glass match, the bound (`hispeed_freq` ≤ `scaling_max_freq`); measurement axis: `input_boost` 1 against 0 in the navigation scenario (smoothness and drain).
- [ ] **Step 2:** `docs/hardware-checks.md`, a NOT RUN section: `dmesg | grep 'cpufreq_interactive_input_connect: connect to sensor00fn11'`; `input_boost` reads 1; with tracing, `cpufreq_interactive_boost: input` events while swiping and none at rest; `time_in_state` delta at `hispeed_freq` during 30 s of swiping, `input_boost` 1 against 0; `input_boost` 0 stops the events; XE24's power HAL or init writing `boostpulse` on touch already (check `logcat`/trace), which would make the kernel boost redundant.
- [ ] **Step 3:** README Status: "Phase 6: touchpad input boost in the tuned builds", not run on hardware.
- [ ] **Step 4:** Commit: `Document the touchpad input boost`. Rebase on `main` before merging (another PR may land in parallel), wait for CI, independent review, `gh pr merge --merge`.

## Decision for the owner

- The default is **on** (`0007`), as the phase asks. Under the kernel defaults, `hispeed_freq` is 1008 MHz, so every touchpad report can raise the CPU to the NITRO point for 80 ms when the thermal table allows. Whether that costs measurable heat or battery is unmeasured; `input_boost` 0, or a profile with a lower `hispeed_freq`, reverses it at runtime.
