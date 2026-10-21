# Phase 3: GPU module from source — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `pvrsrvkm_sgx540_120.ko` from Imagination's SGX DDK at XE24's exact version, `1.9@2166536`, next to our kernel. The XE24 user-space PowerVR libraries, extracted from the owner's image, then keep working with a module we can rebuild for any kernel config.

**Architecture:**
- Pin the DDK the same way the kernel is pinned. The source is `proprietary/imgtec/eurasia_km` in `KFire-Android/android_vendor_amazon_otter` at commit `7d7692662a6d906fe074475602ae3085aa4e35cd`, "IMG DDK 1.9@2166536 for Android". Its licence is dual MIT/GPL-2.0, per its `README`.
- Fetch only that directory into `pvr/`, with a blobless sparse checkout. The rest of that repository holds binaries we never download.
- `build.sh` builds the module after `zImage`, with the DDK's own `omap4430_android` makefiles.
- A compare tool checks the built module against the stock XE24 module on the owner's machine.

**Tech stack:** POSIX sh, the existing Ubuntu 14.04 / GCC 4.7 container, GitHub Actions, Python 3 stdlib for the compare tool.

**Spec:** glass-rom [`docs/plans/2026-10-21-open-source-roadmap.md`](https://github.com/OpenMyGlass/glass-rom/blob/main/docs/plans/2026-10-21-open-source-roadmap.md), phase R2, first half. Facts about the stock module are in glass-rom [`docs/xe24-blobs.md`](https://github.com/OpenMyGlass/glass-rom/blob/main/docs/xe24-blobs.md):
- DDK `SGX_DDK_Android sgxddk 19 1.9@2166536`;
- vermagic `3.4.94-01990-g1cee760235d SMP preempt mod_unload modversions ARMv7 p2v8`;
- SHA-256 `a4a60b4e3cfd4ff010e9c3300abf484171e5f291b3b7b5fd695f74e3b3e58afc`.

## Global constraints

- Kernel code and patches are GPL-2.0-only. The DDK keeps its MIT/GPL-2.0 dual licence and is not vendored: it is fetched at a pinned commit, like `src/`.
- No Google file, and nothing extracted from one, goes into the repo, CI or artifacts. The compare tool reads the stock module only from a path the owner passes on the command line.
- Builds stay bit-for-bit reproducible. The module joins the files `check-reproducible.sh` compares.
- Builds run only in the container (`build-in-container.sh`) and in CI. There is no docker on the owner's Mac, so implementers verify builds by pushing the branch and reading the CI run.
- `VARIANT=stock` and `VARIANT=tuned` both build the module.
- English. Shell scripts pass `shellcheck -s sh`.

## Review focus

1. If the pinned DDK commit or path disappears, or `pvrversion.h` is not `1.9` / `2166536`, the fetch must stop with an error naming what it found, rather than build another DDK (Task 1, `version check`).
2. If the DDK makefiles silently skip the module, the build must fail rather than ship an artifact without a `.ko` (Task 2, `test -s` on the output).
3. A module built against a kernel with a different `LOCALVERSION` or config must be reported by the compare tool as a vermagic difference, not as a match (Task 3, `test_vermagic_differs`).
4. Running the compare tool on a non-ELF file or on a 64-bit ELF must give a clear error, not a traceback (Task 3, `test_rejects_non_elf32`).
5. Two builds of the same commits must give an identical `.ko` (Task 2, the repro workflow).

---

### Task 1: Pin and fetch the DDK

**Files:**
- Modify: `scripts/source.env`. Add:
  - `PVR_REPO=https://github.com/KFire-Android/android_vendor_amazon_otter.git`
  - `PVR_COMMIT=7d7692662a6d906fe074475602ae3085aa4e35cd`
  - `PVR_PATH=proprietary/imgtec/eurasia_km`
  - `PVR_EXPECTED_BUILD=2166536`
  - `PVR_EXPECTED_BRANCH=1.9`
- Create: `scripts/fetch-pvr.sh`
- Modify: `scripts/build-in-container.sh` and both workflows, to run `scripts/fetch-pvr.sh` after `scripts/fetch-source.sh`.
- Modify: `.gitignore`, adding `pvr/`.

**Interfaces:**
- Produces: `pvr/` is a git checkout at `PVR_COMMIT` with only `PVR_PATH` checked out. Its DDK root is `pvr/$PVR_PATH`, and Task 2 builds from there.

- [ ] **Step 1: Write `scripts/fetch-pvr.sh`.**
  - `git init` `pvr/`, add `PVR_REPO` as `origin`, then `git fetch --depth 1 --filter=blob:none origin $PVR_COMMIT`.
  - Set `sparse-checkout` to `PVR_PATH` and check out `PVR_COMMIT`. Skip the fetch when `pvr/` is already at `PVR_COMMIT`.
  - Then read `pvr/$PVR_PATH/include4/pvrversion.h` and check that `PVRVERSION_BRANCHNAME` is `"1.9"` and `PVRVERSION_BUILD` is `2166536`. On a mismatch, exit 1 with `error: DDK is <branch>@<build>, expected 1.9@2166536`. On success, print `pvr/ at <commit> (DDK 1.9@2166536)`.
- [ ] **Step 2:** Run `shellcheck -s sh scripts/fetch-pvr.sh`. Expected: no output.
- [ ] **Step 3:** Wire it into `build-in-container.sh` and the two workflows, then commit with the message `Fetch the SGX DDK 1.9@2166536 at a pinned commit`.

### Task 2: Build the module

**Files:**
- Modify: `scripts/build.sh`
- Modify: `scripts/check-reproducible.sh`
- Modify: `.github/workflows/build.yml`, adding the `.ko` to the artifact.

**Interfaces:**
- Consumes: `pvr/$PVR_PATH` from Task 1, and the configured, built kernel tree in `out/build` that `build.sh` already produces.
- Produces: `out/pvrsrvkm_sgx540_120.ko` (stripped with `--strip-unneeded`), listed in `out/SHA256SUMS`.

- [ ] **Step 1: Build the module in `build.sh`, after `zImage`.**
  - First run `make -C src O="$BUILD" -j"$(nproc)" modules_prepare`.
  - Then run the DDK's own makefile from `pvr/$PVR_PATH/eurasiacon/build/linux2/omap4430_android`, with `ARCH=arm`, `CROSS_COMPILE` and `KERNEL_CROSS_COMPILE` = `arm-linux-gnueabi-`, `KERNELDIR=$BUILD`, `KERNEL_SRC=$PWD/src` (only if the DDK makefiles need it), `BUILD=release`, `TARGET_PRODUCT=blaze_tablet`, `TARGET_SGX=540` and `PLATFORM_VERSION=4.0`.
  - These values come from the build that the existing Glass AOSP tree uses. If the DDK needs `omapfb.h` in the output tree, copy `src/drivers/video/omap2/omapfb/omapfb.h` to `$BUILD/drivers/video/omap2/omapfb/` first, as that build does.
  - Build into a directory under `out/`, never inside `pvr/`, so the checkout stays clean. If the DDK makefiles cannot build out of tree, copy `pvr/$PVR_PATH` to `out/pvr-build/` first.
- [ ] **Step 2:** Copy the result to `out/pvrsrvkm_sgx540_120.ko` and strip it with `arm-linux-gnueabi-strip --strip-unneeded`. Fail with `error: pvrsrvkm_sgx540_120.ko was not built` unless `test -s` passes. Add the `.ko` to the `sha256sum` line.
- [ ] **Step 3:** Add `pvrsrvkm_sgx540_120.ko` to the files `check-reproducible.sh` compares, next to `zImage`.
- [ ] **Step 4: Verify through CI.**
  - Push the branch `gpu-module` (this repo's PR flow) and read the `build` run for both variants.
  - Expected: both pass, both artifacts contain the `.ko`, and the logs show the `fetch-pvr.sh` success line.
  - If a build error comes from DDK 1.9 vs Linux 3.4.94 API drift, fix it with the smallest patch under `pvr-patches/`, applied by `build.sh` to the copy in `out/pvr-build/`, never to `pvr/`. Name each patch after what it fixes.
- [ ] **Step 5:** Trigger the `repro` workflow (`workflow_dispatch`). Expected: `pvrsrvkm_sgx540_120.ko: identical`.
- [ ] **Step 6:** Commit with the message `Build pvrsrvkm_sgx540_120.ko from the DDK with the kernel`.

### Task 3: Compare tool

**Files:**
- Create: `scripts/compare_ko.py`
- Create: `tests/test_compare_ko.py`, run with `python3 -m unittest discover -s tests -v`. Add that step to the `build.yml` `tuning` job.

**Interfaces:**
- Produces:
  - `read_module(data: bytes) -> dict` returns these keys:
    - `modinfo`: the `.modinfo` key/value pairs as `dict[str, list[str]]`;
    - `versions`: `__versions` CRC entries as `dict[str, int]`;
    - `undefined`: undefined global symbol names from `.symtab`, as a sorted `list[str]`;
    - `ddk`: the first `SGX_DDK_Android …` string in the file, or `None`.
  - `compare(stock: dict, built: dict) -> list[str]` returns human-readable differences. An empty list means a match. It reports:
    - vermagic, compared without the `LOCALVERSION` part (the text between `3.4.94` and the first space);
    - the DDK string;
    - symbols in `stock.undefined` but not in `built.undefined`, and the reverse;
    - CRCs that differ for a symbol present in both `versions`;
    - `modinfo` `parm`/`parmtype` names present in only one module.
  - `main(argv) -> int` with usage `compare_ko.py STOCK.ko BUILT.ko`. It prints the differences and returns 0 on a match, 1 on differences, and 2 on unreadable input.
  - `class ModuleError(Exception)`.

- [ ] **Step 1: Write the failing tests.**
  - The test helper `make_elf32(sections: dict[str, bytes], symbols: list[tuple[str, int]]) -> bytes` builds a minimal little-endian ELF32 relocatable with those sections, a `.symtab` and a `.strtab`. A symbol whose `shndx` is 0 is undefined.
  - `test_reads_modinfo_versions_symbols`: `.modinfo` contains `vermagic=3.4.94-x SMP preempt\0parm=foo:bar\0`, `__versions` holds one entry (CRC `0x1234`, name `printk`), and there are undefined `printk` and `kmalloc`. `read_module` returns exactly those values, with `ddk` set to `None`.
  - `test_ddk_string`: a `.rodata` containing `SGX_DDK_Android sgxddk 19 1.9@2166536\0` gives `ddk == "SGX_DDK_Android sgxddk 19 1.9@2166536"`.
  - `test_match_ignores_localversion`: vermagic `3.4.94-01990-g1cee760235d SMP preempt mod_unload modversions ARMv7 p2v8` against `3.4.94-openmyglass SMP preempt mod_unload modversions ARMv7 p2v8` gives `[]`.
  - `test_vermagic_differs`: `… SMP preempt …` against `… SMP mod_unload …` gives one difference that mentions `vermagic`.
  - `test_symbol_and_crc_differences`: one symbol only in stock, and one shared symbol with different CRCs, give two differences naming each symbol.
  - `test_rejects_non_elf32`: `b"not an elf"` and a 64-bit ELF header (`EI_CLASS=2`) both raise `ModuleError`, and `main` returns 2 for them.
- [ ] **Step 2:** Run the tests. Expected: FAIL (import error).
- [ ] **Step 3:** Implement `scripts/compare_ko.py` with `struct` only. Parse the section headers, `.symtab` / `.strtab`, `.modinfo` and `__versions` (64-byte entries: a 4-byte CRC, then a 60-byte NUL-padded name).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit with the message `Compare a built kernel module with the stock one`.

### Task 4: Compare on the owner's machine, and document

**Files:**
- Create: `docs/gpu-module.md`
- Modify: `README.md` (Status, Building), `docs/hardware-checks.md`

- [ ] **Step 1: Run the compare.** Download the `kernel-stock` artifact from the Task 2 CI run. Run `python3 scripts/compare_ko.py STOCK.ko out/pvrsrvkm_sgx540_120.ko`, with the stock module dumped from the owner's XE24 system image.
  - Expected:
    - the DDK string matches;
    - vermagic matches apart from `LOCALVERSION`;
    - the list of kernel symbols the module imports is the same, or only adds or removes symbols with a clear reason.
  - CRC differences are expected, because our kernel is xrx13b and not XE24's `1cee760`, and the module only ever loads into the kernel it was built with. Record them, but do not treat them as failures.
- [ ] **Step 2: Write `docs/gpu-module.md`.**
  - Which DDK, from where, and why this build. The alternative, OMAP4-AOSP's `pvr-source` at `1.9@2291151`, would need user-space libraries from another device.
  - How the module is built.
  - The compare result as facts: matching fields, differing symbol names and counts. No module contents.
  - What it unlocks: config changes that alter structures used by the module are now possible, because the module is rebuilt with the kernel.
- [ ] **Step 3: Update the README and the hardware checks.**
  - `README.md` Status: Phase 3, GPU module from source.
  - `docs/hardware-checks.md`: a new section for after the first `fastboot boot` of our kernel. Load our module, run XE24's `pvrsrvinit`, check that `dmesg` has no `PVRSRV_ERROR_DDK_VERSION_MISMATCH` or `BUILD_MISMATCH`, and check that SurfaceFlinger starts.
- [ ] **Step 4:** Commit with the message `Document the GPU module build and how it compares with stock`, then open the pull request against `main`.
