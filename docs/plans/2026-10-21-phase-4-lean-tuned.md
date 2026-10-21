# Phase 4: A lean `tuned` kernel — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `tuned` variant cheaper to run. It turns off the debugging and tracing options in `notle_defconfig` that cost time on every lock, interrupt toggle or schedule, and backports two later improvements to the interactive governor. `stock` stays exactly Google's source and config.

**Architecture:**
- Since phase 3 the GPU module is rebuilt with the kernel, so config changes that alter structure layouts (lock debugging) are now possible.
- Config changes go in `configs/tuned.config`, which `build.sh` already applies and verifies.
- Source changes are patches under `patches/tuned/`, applied only when `VARIANT=tuned`.
- `tuning/omg-tune.sh` learns the new governor knob and falls back cleanly on kernels without it.

**Tech stack:** Kconfig fragments, `git apply` patches, POSIX sh, GitHub Actions. Builds run in CI only: there is no docker on the owner's Mac.

**Spec:** glass-rom roadmap, phase R2 second half, and `reports/Ottimizzazioni kernel OMAP4.md`, which ranks changes by risk. Only items rated no or low risk are in this phase. Not in it: overclock, undervolt, GPU frequency, raised thermal limits, the 3.4.y stable merge, the xrr02 input boost.

## Global constraints

- Kernel code and patches are GPL-2.0-only. Each backported patch keeps the original author's `From:` and message, and adds `(cherry picked from commit <sha> in AOSP kernel/common <branch>)`. Adapted hunks are noted in the message.
- `VARIANT=stock` produces exactly what it produced before this phase. Its `zImage` and `.ko` SHA-256 do not change: stock `zImage` is unchanged, and stock `.ko` stays `1ec003f32c94512564404bd80b9802f8715d1995df017c5bfae9b99c0cc991c8`.
- Builds stay reproducible (the repro workflow), and both variants still build `pvrsrvkm_sgx540_120.ko`.
- No Google file, and nothing extracted from one, goes into the repo or CI.
- `PM_DEBUG` stays on, because OMAP's off-mode switches live under it. `DEBUG_FS` stays on, because power and thermal tools read it. `FTRACE` and `TRACEPOINTS` stay on, because Android's `atrace` and `systrace` use event tracing, which costs nothing while it is off.
- English. Shell passes `shellcheck -s sh`.

## Review focus

1. If Kconfig silently re-enables a disabled option through a `select`, the build must fail. `build.sh` already checks `# … is not set` lines (Task 1, CI log).
2. A patch meant for `tuned` must never touch `stock`. The stock hashes stay the same (Task 2, CI log comparison).
3. On a kernel without per-frequency `above_hispeed_delay`, such as the stock XE24 kernel, `omg-tune.sh` must fall back to a single value and still exit 0. It must not leave the governor half-set (Task 3, `test_fallback_single_delay`).
4. When a patch no longer applies after a source pin bump, the build must stop. `build.sh` already runs `git apply --check` (Task 2).
5. `omg-tune.sh status` must print the new knob when present and skip it silently when absent (Task 3).

---

### Task 1: Lean config for `tuned`

**Files:**
- Modify: `configs/tuned.config`
- Modify: `docs/tuning.md` (section "The `tuned` build")

- [ ] **Step 1: Add these lines to `configs/tuned.config`,** each as `# CONFIG_X is not set`, under a comment heading "Debugging and tracing with a runtime cost":
  - `DEBUG_SPINLOCK`, `DEBUG_MUTEXES`, `DEBUG_RT_MUTEXES`, `DEBUG_PI_LIST`;
  - `IRQSOFF_TRACER`, `FUNCTION_TRACER`, `FUNCTION_GRAPH_TRACER`, `FUNCTION_PROFILER`;
  - `SCHEDSTATS`, `TIMER_STATS`, `KPROBES`, `OPROFILE`.
- [ ] **Step 2: Build the `tuned` variant through CI.** Push branch `lean-tuned`, then run `gh workflow run build.yml --ref lean-tuned` and `gh run watch`.
  - Expected: both variants pass.
  - Expected: the `tuned` log has no `Kconfig kept` or `Kconfig dropped` error.
  - Expected: the `stock` log's SHA256SUMS lines are identical to those of run 39646474843.
  - If an option comes back through a `select`, add the selecting option to the fragment only if that option is itself debug-only. Otherwise drop the line and record why.
- [ ] **Step 3:** Record in `docs/tuning.md` which options are off and why each costs time at runtime (one line each), and which debug options stay on and why. Record the `tuned` `zImage` size against `stock`, both taken from the CI logs.
- [ ] **Step 4:** Commit with the message `Turn off lock debugging and runtime tracers in the tuned build`.

### Task 2: Variant patches and the interactive backports

**Files:**
- Modify: `scripts/build.sh`, so that it applies `patches/*.patch` (all variants, none today), then `patches/tuned/*.patch` when `VARIANT=tuned`, with the same `--check`-then-apply loop.
- Create: `patches/tuned/0001-…patch`, `patches/tuned/0002-…patch`.
- Modify: `.github/workflows/repro.yml`, adding `patches/**` and `configs/**` to the pull_request paths filter.

**Interfaces:**
- Produces, on the `tuned` kernel:
  - `/sys/devices/system/cpu/cpufreq/interactive/above_hispeed_delay` accepts and prints `D` or `D F:D …` (per-frequency, the same syntax as `target_loads`);
  - `/sys/devices/system/cpu/cpufreq/interactive/io_is_busy` (0 or 1, default 0) exists.
  - *Amendment (during execution):* by ruling, patch 0005 sets the default to 1 to keep the stock accounting; 0 remains an option to measure.

- [ ] **Step 1: Find the upstream commits.** In AOSP `kernel/common` (`android-3.4`, else `android-3.10`), find the commits that add:
  - (a) per-frequency `above_hispeed_delay` (Todd Poynor, "cpufreq: interactive: allow arbitrary speed / delay mappings for above_hispeed_delay" or similar);
  - (b) `io_is_busy` ("cpufreq: interactive: add io_is_busy interface" or similar).

  Use gitiles `+log/...?format=JSON` or the `aosp-mirror` GitHub mirrors. Record both SHAs.
- [ ] **Step 2: Turn each commit into a patch** with `git format-patch`, rebased onto `drivers/cpufreq/cpufreq_interactive.c` at our pinned `COMMIT`. Glass's file already has `boostpulse_duration`, `timer_slack` and single-value `above_hispeed_delay`.
  - Adapt the patch only where context differs. Note each adaptation in the message.
  - If (a) needs an intermediate upstream commit, include that commit as its own patch instead of squashing.
- [ ] **Step 3: Verify through CI.**
  - Expected: `tuned` applies both patches (the log shows `applying patches/tuned/…`) and builds.
  - Expected: the `stock` hashes are unchanged.
  - Expected: the `repro` workflow gives `identical`.
- [ ] **Step 4:** Commit with the message `Backport per-frequency above_hispeed_delay and io_is_busy to the tuned build` (the patches, the build.sh change and the workflow filter).

### Task 3: `omg-tune.sh` uses the per-frequency delay

**Files:**
- Modify: `tuning/omg-tune.sh`
- Modify: `tests/test_omg_tune.sh`

**Interfaces:**
- Consumes: per-frequency `above_hispeed_delay` from Task 2. It may be absent on stock kernels.

- [ ] **Step 1: Write the failing tests** in `tests/test_omg_tune.sh`, in its existing style:
  - `balanced` on a fake sysfs whose `above_hispeed_delay` accepts any string: the file ends as `40000 800000:60000`.
  - `cool`: the file ends as `60000 800000:80000`.
  - `test_fallback_single_delay`: make the fake file reject multi-value writes. Do this with a fake that a test-only hook in the script treats as "reads back the first token only", or with any approach that needs no kernel. `balanced` must then write the single value `40000`, exit 0, and print no failure.
  - `status` prints `above_hispeed_delay` and `io_is_busy` when they exist, and does not mention `io_is_busy` when it is missing.
- [ ] **Step 2:** Run `sh tests/test_omg_tune.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `stock` keeps `20000`.
  - `balanced` writes `40000 800000:60000` and `cool` writes `60000 800000:80000`. Both profiles keep the CPU at or below 800 MHz longer before NITRO.
  - When the read-back is not the multi-value string, write the single first value and accept it.
  - `status` lists `io_is_busy` when it exists.
  - Profiles do not set `io_is_busy`: it is left at the kernel default (0) until it is measured. *(Amended: the kernel default is 1 via patch 0005, see above.)*
- [ ] **Step 4:** Run `sh tests/test_omg_tune.sh` and `shellcheck -s sh tuning/omg-tune.sh tests/test_omg_tune.sh`. Expected: PASS and no output.
- [ ] **Step 5:** Commit with the message `Use per-frequency above_hispeed_delay where the kernel supports it`.

### Task 4: Docs and measurement plan

**Files:**
- Modify: `docs/tuning.md` (profiles table, measurement plan), `README.md` (Status), `docs/hardware-checks.md` (only if a boot check changes)

- [ ] **Step 1: Update the docs.**
  - The profiles table gets the new `above_hispeed_delay` values.
  - The measurement plan gets one more axis: the `stock` build against the `tuned` build, each with the `stock` profile, in the same three scenarios. That separates the config effect from the profile effect.
  - The README Status gets "Phase 4: lean tuned build (no lock debugging or runtime tracers; per-frequency above_hispeed_delay, io_is_busy)", not measured on hardware.
- [ ] **Step 2:** Commit with the message `Document the lean tuned build and how to measure it`. Then open the pull request against `main`.
