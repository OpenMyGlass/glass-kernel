# `hispeed_freq` ceiling: clamp instead of drop — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `tuned` and `tuned-stable`, a CPU target above `hispeed_freq` runs at `hispeed_freq` instead of being ignored, which could drop the CPU to its lowest speed under load. The `omg-tune.sh` profiles stop relying on a `hispeed_freq` below the maximum, so they behave the same on every kernel. `stock` stays exactly Google's source and config.

**Architecture:**
- Glass's speed-change task keeps only per-CPU targets `<= hispeed_freq` (Google commit `82ecdfc2408b`); AOSP has no such term. `patches/tuned/0009` (OpenMyGlass) clamps each target to `hispeed_freq` instead. The ceiling stays.
- Profiles set `hispeed_freq` = `scaling_max_freq`; caps go through `scaling_max_freq`. The script orders the two writes so `hispeed_freq` is never below the maximum.

**Tech stack:** `git apply` patches, POSIX sh, GitHub Actions. Builds run in CI only.

## Global constraints

- Safety: every speed set by the patched governor is at or below `hispeed_freq`, as in the stock code, and still within `scaling_min_freq`–`scaling_max_freq` and the thermal limit (`omap_target()`, `omap_cpufreq_scale()`). No profile goes above 1008 MHz, and none chooses a higher speed than `stock` at the same load (`go_hispeed_load` 99, target loads 90 or more). No OPP, voltage or thermal table changes.
- `VARIANT=stock` is byte-identical: `zImage` `5b744fef8f8688562e19b8311225f324037aad49901ed78ee6854529de15caa1`, `.ko` `1ec003f32c94512564404bd80b9802f8715d1995df017c5bfae9b99c0cc991c8`.
- Builds stay reproducible; the GPU modules' imported CRCs are unchanged (`scripts/compare_ko.py`).
- Device checks are written and marked NOT RUN. English. Shell passes `shellcheck -s sh`.

## Findings

- `drivers/cpufreq/cpufreq_interactive.c` at `989d925` (and, byte-identical, at the `tuned-stable` merge `b6ea856`):
  `if ((pjcpu->target_freq > max_freq) && (pjcpu->target_freq <= hispeed_freq)) max_freq = pjcpu->target_freq;`
- Origin: `82ecdfc2408b` "Interactive Governor: Add checks to prevent deadlock in worker" (Kai Yick, Google, 2013-11-13, `Change-Id: Ib1d938ae0d47b5ffad1957438765880a0289c5ba`), found with the GitHub commits API on OpenMyGlass/kernel-omap (gitiles history needs sign-in). The message does not explain the term.
- If every target is above `hispeed_freq`, `max_freq` is 0; `__cpufreq_driver_target(policy, 0, CPUFREQ_RELATION_H)` reaches `cpufreq_frequency_table_target()`, which finds no frequency `<= 0` and returns the lowest one within the policy (the "suboptimal" entry). The timer does not requeue while its target is unchanged.
- The old `balanced`/`cool` profiles wrote `hispeed_freq` 600 MHz: they never ran above 600 MHz and could fall to 300 MHz under load.

---

### Task 1: The patch

- [ ] **Step 1:** In a tree with `cpufreq_interactive.c` and `governors.txt` from `989d925` and `0001`–`0008` applied (`git am`), count `min(target_freq, hispeed_freq)` per CPU; read `hispeed_freq` once per policy; document the ceiling in `governors.txt`. Author OpenMyGlass.
- [ ] **Step 2:** `git format-patch --zero-commit --no-signature`, save as `patches/tuned/0009-…`.

### Task 2: `omg-tune.sh`

- [ ] **Step 1: Failing tests:** profile values (`balanced` 1008000/1008000/99/`90 800000:95`/20000; `cool` 800000/800000/99/90/20000); the first-token fallback now through `balanced`'s `target_loads`; `hispeed_before_max` ordering; `cool` with an unwritable `scaling_max_freq` leaves `hispeed_freq` at 1008000 and exits 1.
- [ ] **Step 2:** Implement; `sh tests/test_omg_tune.sh`, `shellcheck -s sh`.

### Task 3: CI, hashes, docs

- [ ] **Step 1:** CI green; `stock` hashes as above; `repro` `identical` for all three variants; `compare_ko.py` against main's modules.
- [ ] **Step 2:** `docs/tuning.md` (ceiling, `0009`, profiles, new hashes), `docs/hardware-checks.md` (NOT RUN), README Status.

## Decision for the owner

- The old profiles effectively capped the CPU at 600 MHz. The new `balanced` reaches 1008 MHz and `cool` 800 MHz, as their docs always said: both hotter than what actually ran before, never above `stock`. If a 600 MHz cap is wanted, it is a new profile with `scaling_max_freq` 600000.
- Whether Google's ceiling should go (AOSP behaviour) is left open: it needs measurements.
