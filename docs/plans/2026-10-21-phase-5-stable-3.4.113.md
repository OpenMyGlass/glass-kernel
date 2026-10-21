# Phase 5: linux-3.4.y 3.4.113 — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the kernel from Linux 3.4.94 to 3.4.113, the final linux-3.4.y stable release (2016-10-26), with 1450 upstream fixes. It goes into a new `tuned-stable` build variant. `stock` stays exactly Google's source and config, and `tuned` stays as it is.

**Architecture:**
- The merge is an ordinary `git merge` of tag `v3.4.113` into Google's pinned `glass-omap-xrx13b` commit. It is published as one merge commit on a branch of a new repository, `OpenMyGlass/kernel-omap`, pinned in `scripts/source.env` as `STABLE_*`.
- The kernel source is still not vendored here. `scripts/fetch-source.sh` makes a depth-1 fetch of the pinned commit of the variant being built.
- `scripts/variant.sh` maps `VARIANT` to the source pin and says whether the tuned config and patches apply. `tuned-stable` is `tuned` (`configs/tuned.config`, `patches/tuned/`) on the merged source.
- `scripts/check-stable-merge.sh` re-creates the merge from its inputs. It runs git's own merge, applies the conflict resolutions kept in `stable-merge/v3.4.113-resolutions.patch`, and checks that the result has the pinned commit's tree and parents. CI runs it.

**Tech stack:** git (merge-ort, `merge-tree --write-tree`, 2.38 or newer, on the host and in CI), POSIX sh, GitHub Actions. Kernel builds run in CI only.

**Spec:** glass-rom roadmap, phase R2: "the 3.4.y stable merge", left out of phase 4.

## Approach, and why

Options considered:

| Option | What it is | Verdict |
|---|---|---|
| (a1) Merge `v3.4.113` into the pinned commit, publish it as a branch pinned by commit | one merge commit; upstream commits keep their identity and authorship | **chosen** |
| (a2) The same merge, exported as patch files in this repository | 1450 patch files, or one diff of about 22,000 lines | rejected: unreviewable, loses upstream commit identity, and `git apply` of 1450 patches on every build is slow |
| (b1) invisiblek/android_kernel_google_glass `master` | Glass kernel with `glass-omap-xrx13b` merged and linux-3.4.y merged up to **3.4.105** (2014-12-14) | rejected as a base: it stops 8 releases short, its two merges (c41efb12, bd4bc643) resolve conflicts without any record, and its history has unrelated personal changes (`-O3`, Linaro 4.9, lz4 boot changes, smartass governor). No license file beyond the kernel's GPL-2.0 `COPYING` |
| (b2) Unlegacy-Android/android_kernel_ti_omap4 `3.4/espresso`, `3.4/nookhd` (3.4.113), `3.4/common` (3.4.112) | TI's OMAP4 3.4 tree for the Galaxy Tab 2 and Nook HD, with stable merged | rejected as a base: it is TI's tree, not Google's Glass tree, and it has no notle board, duty-cycle governor, glasshub or Glass display code. Taking it would mean re-porting all Glass code. GPL-2.0 (`COPYING`) |

Why (a1):
- **Reproducible.** The merge's inputs are pinned (Google's commit, the PGP-signed upstream tag, and the commit it points to) and its output is pinned by commit SHA. `check-stable-merge.sh` re-creates the tree from the inputs plus the resolutions patch, so anyone can check that nothing else was changed.
- **Reviewable.** git merges only 5 files with conflicts. The 61 other files that both sides changed merge cleanly, and for each of them the change against Google's file is exactly stable's change (checked line by line, see `docs/stable-merge.md`). Review therefore comes down to the resolutions patch (2 files, 4 hunks), one dwc3 decision, and the list of upstream changes in power-related code.
- **Auditable.** Every conflict is listed with file, reason and kept side in `docs/stable-merge.md`. The prior work is used as an independent cross-check: both hand-resolved files are byte-identical to Unlegacy-Android's 3.4.113 merges.
- **Small and fast for builds.** CI fetches one commit at depth 1, as it does for Google's source.

Why a new repository (`OpenMyGlass/kernel-omap`) and not a fork: Google's source is on googlesource, not GitHub, so there is no GitHub repository to fork. A fork of invisiblek's repository would import his unrelated branches. The new repository holds two branches: `glass-omap-xrx13b`, an unchanged mirror of Google's branch at the pinned commit, and `glass-omap-xrx13b-stable-3.4.113`, the merge (default branch). Both are protected against deletion, force-push and any update. A later merge gets a new branch, so every pin in `source.env` keeps working.

Why a new variant and not `tuned`:
- Nothing has run on hardware yet. Each variant adds one class of change: `stock` (Google), `tuned` (config and governor patches), `tuned-stable` (plus 1450 upstream fixes). If a boot fails, the first variant that fails says which class to look at.
- The phase 4 measurement plan compares `stock` and `tuned`; changing `tuned` underneath it would mix two effects.
- `tuned-stable` and not plain `stable`: it carries the tuned config and patches, and the name says so. A stable variant without the tuned changes is one line in `variant.sh` if it is ever wanted.

## Global constraints

- Kernel code is GPL-2.0-only. The merge commit keeps every upstream commit as it is (authorship, message, SHA). The resolutions patch and the merge message are OpenMyGlass work.
- `VARIANT=stock` stays byte-identical: `zImage` SHA-256 `5b744fef8f8688562e19b8311225f324037aad49901ed78ee6854529de15caa1` and `.ko` `1ec003f32c94512564404bd80b9802f8715d1995df017c5bfae9b99c0cc991c8` (main CI run 39657896376). `tuned` also stays as it is: `zImage` `a4f3215246c4fa96f3bec15fadadf3cd70d9ed0ed72d99c400d80118618c1041`, `.ko` `69afa570c35808286acdb3d13e034c665eb3c7ea4105016914ff86bc33d4bb9c` (same run).
- The PowerVR module (DDK 1.9@2166536) builds against `tuned-stable`. Its imports and CRCs are compared with `scripts/compare_ko.py`, and every changed CRC is documented.
- Builds stay reproducible: the repro workflow covers `tuned-stable` too.
- No Google file, and nothing extracted from a Google image, goes into this repository or CI. The stock XE24 module used for `compare_ko.py` stays on the owner's machine. The new repository holds only Google's published GPL-2.0 source and its merge.
- No change to voltages, OPPs, thermal limits, charger or fuel-gauge parameters beyond what upstream stable itself changes. Any such upstream change is flagged in `docs/stable-merge.md`. Nothing touches the bootloader, xloader or FPGA.
- Nothing is tested on hardware. Device checks go to `docs/hardware-checks.md`, marked as not run.
- English. Shell passes `shellcheck -s sh`.

## Review focus

1. The two hand resolutions (`xt_socket.c`, `sound/usb/card.c`): does each keep both sides' intent (Task 1, resolutions patch)?
2. Keeping Google's dwc3 whole: is the driver really not built for notle (Task 1, `CONFIG_USB_DWC3`)?
3. Clean merges can still be wrong where Google cherry-picked a fix that stable also carries, because the fix could then be applied twice. Check the duplicate list (Task 1, Step 3).
4. Upstream changes in power, thermal, charging, pinmux and watchdog code: is each harmless on notle (Task 1, Step 4)?
5. `stock` and `tuned` hashes unchanged, and `tuned-stable` reproducible (Task 3).
6. PVR CRC differences between `tuned` and `tuned-stable` (Task 3).

---

### Task 1: The merge

**Files:**
- Create (in `OpenMyGlass/kernel-omap`): branches `glass-omap-xrx13b` (mirror) and `glass-omap-xrx13b-stable-3.4.113` (merge).
- Create: `stable-merge/v3.4.113-resolutions.patch`

- [x] **Step 1: Fetch the inputs.** Partial, shallow clones are enough (history from 2014-04-01): Google's branch, `v3.4.113` from kernel.org stable. Check that the merge base is `v3.4.94` (95f3bb9), which Google merged in 4e256f07.
- [x] **Step 2: Merge.** Run `git merge-tree --write-tree glass-omap-xrx13b v3.4.113`. Expected: a small conflict list. Resolve each conflict by keeping both sides' intent, and stop if a Glass-specific file (board-notle, duty-cycle thermal governor, interactive governor, notle-usb-mux, glasshub, ram_console) conflicts and its resolution is not certain.
  - Result: 5 conflicts (dwc3 ×3, `xt_socket.c`, `sound/usb/card.c`). Stable touches no Glass-specific file.
- [x] **Step 3: Check the clean merges.** For every file both sides changed, compare stable's line changes with what the merge changes in Google's file, and list the stable commits that Google had already cherry-picked (matched by upstream SHA and by subject).
  - Result: identical for all 61 cleanly merged files except `fs/ext4/mballoc.c`, where Google already had stable's one-line fix (b5b60778), so it is applied once.
- [x] **Step 4: List the upstream changes in power-related code** (regulator, cpufreq, power supply, thermal, mfd, mach-omap2, watchdog, PM core, timekeeping) and say for each whether it is built on notle and whether it changes a value.
- [x] **Step 5: Cross-check** the resolutions against invisiblek's and Unlegacy-Android's merges.
- [x] **Step 6: Create the repository and push.** `gh repo create OpenMyGlass/kernel-omap --public`. Push both branches from a full single-branch clone, then add the rulesets: `protect-main` (as in glass-kernel: no deletion, no force-push, changes by pull request) on the default branch, and `freeze-pinned-branches` (no deletion, no force-push, no update) on all branches.

### Task 2: Build the new variant

**Files:**
- Create: `scripts/variant.sh`, `scripts/check-stable-merge.sh`
- Modify: `scripts/source.env` (`STABLE_*`), `scripts/fetch-source.sh`, `scripts/build.sh`, `.github/workflows/build.yml`, `.github/workflows/repro.yml`

**Interfaces:**
- `VARIANT=tuned-stable scripts/build-in-container.sh` builds `out/zImage` and `out/pvrsrvkm_sgx540_120.ko` from `STABLE_COMMIT`, with `configs/tuned.config` and `patches/tuned/`.
- `scripts/check-stable-merge.sh [workdir]` exits 0 only when `STABLE_COMMIT` is the documented merge.

- [ ] **Step 1:** Write `variant.sh` and make `fetch-source.sh` and `build.sh` use it. For `stock` and `tuned`, the fetched commit, patches and config stay the same.
- [ ] **Step 2:** Write `check-stable-merge.sh` and run it locally. Expected: `tree c8dc0475…: git's merge plus the documented resolutions`.
- [ ] **Step 3:** Add `tuned-stable` to the build and repro matrices, and a `stable-merge` CI job that runs the check script.
- [ ] **Step 4:** `shellcheck -s sh scripts/*.sh`. Expected: no output.
- [ ] **Step 5:** Commit with the message `Add the tuned-stable variant, on linux-3.4.y 3.4.113`.

### Task 3: Verify through CI

- [ ] **Step 1:** Push branch `stable-3.4.113` and run `gh workflow run build.yml --ref stable-3.4.113` and `gh workflow run repro.yml --ref stable-3.4.113`.
  - Expected: all jobs pass, and the `tuned-stable` log shows `applying patches/tuned/…` and no Kconfig error.
  - Expected: the `stock` and `tuned` SHA256SUMS lines are identical to those of main run 39657896376.
  - Expected: repro reports `identical` for all four files in all three variants.
  - Expected: `stable-merge` passes.
- [ ] **Step 2:** Download the `kernel-tuned` and `kernel-tuned-stable` artifacts. Run `scripts/compare_ko.py` with tuned's module against tuned-stable's, and the stock XE24 module (owner's copy, not in the repo) against tuned-stable's. Record every CRC difference and the symbols involved.
  - If a symbol the module imports is gone, or the module does not link: stop and report.
- [ ] **Step 3:** Record the `tuned-stable` hashes and sizes.

### Task 4: Docs

**Files:**
- Create: `docs/stable-merge.md`
- Modify: `README.md` (Status, Source), `docs/hardware-checks.md`, `docs/gpu-module.md`, `docs/tuning.md`

- [ ] **Step 1:** In `docs/stable-merge.md`, record: the approach, the inputs, every conflict (file, why, which side kept), the clean-merge check, the Glass-specific files (none conflicted), upstream changes in power-related code, the PVR CRC differences, and how to re-check.
- [ ] **Step 2:** Add the `tuned-stable` boot checks to `docs/hardware-checks.md`, marked as not run.
- [ ] **Step 3:** Commit with the message `Document the 3.4.113 stable merge`.
- [ ] **Step 4:** Have at least one independent review of the full diff (this repository and the merge itself). Fix the findings, open the pull request, and merge it with a merge commit once CI is green.
