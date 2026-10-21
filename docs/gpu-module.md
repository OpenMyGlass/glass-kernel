# GPU module (pvrsrvkm)

The SGX540 driver, `pvrsrvkm_sgx540_120.ko`, is built from source together with the kernel. `scripts/build.sh` writes it to `out/`.

## Which DDK, and why

- **Source:** KFire-Android/android_vendor_amazon_otter @ `7d7692662a6d906fe074475602ae3085aa4e35cd`, directory `proprietary/imgtec/eurasia_km` ("IMG DDK 1.9@2166536 for Android"). Its README gives a MIT/GPL-2.0 dual licence. Pinned in `scripts/source.env`, fetched by `scripts/fetch-pvr.sh`.
- **Why this one:** XE24's user-space libraries are DDK `1.9@2166536` (`libIMGegl` and `libGLESv2` carry "build 1.9@2166536"), and the DDK checks versions between user space and kernel (`PVRSRV_ERROR_DDK_VERSION_MISMATCH`).
- **Not used:** OMAP4-AOSP `pvr-source` is DDK `1.9@2291151`. Using it would need user-space libraries from another device.

## How it is built

After the kernel (`zImage`, `modules_prepare`), `scripts/build.sh` copies the DDK to `out/pvr-build` and runs the DDK's `omap4430_android` makefiles against the kernel build directory. The exact variables are in `scripts/build.sh`. `PLATFORM_VERSION=4.0` does not change the module compared with 4.4 (KitKat): see [Build options](#build-options-compared-with-the-stock-module).

## Comparison with the stock module

`scripts/compare_ko.py` compares a built module with the stock XE24 module (SHA-256 `a4a60b4e3cfd4ff010e9c3300abf484171e5f291b3b7b5fd695f74e3b3e58afc`). It was run on the module from CI run 39637279820 (artifact `kernel-stock`). Result: "modules match", exit 0.

| Field | Stock | Built |
|---|---|---|
| DDK string | `SGX_DDK_Android sgxddk 19 1.9@2166536` | equal |
| vermagic | `3.4.94-01990-g1cee760235d SMP preempt mod_unload modversions ARMv7 p2v8` | `3.4.94-g989d925 SMP preempt mod_unload modversions ARMv7 p2v8` |
| Imported kernel symbols | 166 | 166, identical |
| `__versions` CRCs | 167 | 167, all identical |
| Module parameter | `gPVRDebugLevel` | `gPVRDebugLevel` |

- Only `LOCALVERSION` differs in vermagic.
- xrx13b exports every symbol the stock module imports, with identical CRCs.
- The built module is stripped (426100 bytes for `stock`, 426092 for `tuned`); the stock one is not (3647097 bytes).
- The module build is reproducible: repro run 39634998806 reports `pvrsrvkm_sgx540_120.ko: identical`.
- The `.ko` SHA-256 is identical across two CI runs on different runners (39637279820 and 39638777984): stock `1ec003f32c94512564404bd80b9802f8715d1995df017c5bfae9b99c0cc991c8`, tuned `e632492d7031f43bbca5888c256ea068b425543865863b12ab95f7f3976ad079`.

## Build options compared with the stock module

Checked offline on 2026-10-21 (facts only: section sizes, read-only strings, symbol names; no disassembly). Inputs: the stock XE24 module (SHA-256 above) and our `kernel-stock` module from CI run 39674266245 (SHA-256 `1ec003f3…`).

**Result: no mismatch found; `scripts/build.sh` is unchanged.**

| Check | Stock | Ours (`stock` variant) |
|---|---|---|
| Printable strings in `.rodata*`, `.modinfo` and the `__*` sections | 1887 unique | identical once the build directory prefix is removed, except `vermagic` |
| Build path | `…/eurasia_km/eurasiacon/binary2_540_120_omap4430_android_release/…` | `omap4430_android`, `TARGET_SGX=540` (SGX 540 rev 120), `BUILD=release` |
| `.data` / `.bss` | 1480 / 20088 bytes | equal |
| `__bug_table` (BUG/WARN sites) / `__mcount_loc` (instrumented functions) | 4824 / 3288 bytes | equal |
| `.rodata` / `__versions` / `.gnu.linkonce.this_module` | 900 / 10688 / 348 bytes | equal |
| `.text` | 191732 bytes | 191352 (−380, 0.2 %) |
| `.init.text` | 476 bytes | 472 |
| `.rodata.str`, `.rodata.str1.4`, `.modinfo` | 82742, 71556, 272 bytes | 28907, 66816, 264: the same strings, with a shorter build path and vermagic |
| Global symbols | 550 | identical; every symbol in ours is also in the stock symbol table |
| Compiler (`.comment`) | `GCC: (GNU) 4.7` | `GCC: (Ubuntu/Linaro 4.7.3-12ubuntu1) 4.7.3` |

- So the code that prints messages is present in both: debug output (`PVRSRV_NEED_PVR_DPF`, `PVRSRV_NEED_PVR_TRACE`, `PVRSRV_NEED_PVR_ASSERT`, `PVRSRV_DUMP_MK_TRACE`, `PVRSRV_USSE_EDM_STATUS_DEBUG`, all set by `omap4430_android/products.mk`), the `/proc` entries, ION and DVFS. Equal `.data`, `.bss`, `__bug_table` and `__mcount_loc` sizes fit the same static data and the same set of functions.
- The `.text` and `.init.text` differences are not explained by these checks. The likeliest cause is the different compiler build (the stock module's `GNU 4.7` versus Ubuntu's Linaro 4.7.3). No option that adds or removes code with strings, static data or whole functions differs.
- The stock module carries DWARF debug info, but its producer string is only `GNU C 4.7`, without the command line.
- **`PLATFORM_VERSION=4.0` versus 4.4:** the DDK reads `PLATFORM_VERSION` only through `common/android/platform_version.mk`: its `is_at_least_*` and `is_future_version` macros and `API_LEVEL`. `is_future_version` is 0 for both. 4.0 and 4.4 both set `is_at_least_icecream_sandwich`, which in `omap4430_android/Makefile` gates the kernel options `SUPPORT_DC_CMDCOMPLETE_WHEN_NO_LONGER_DISPLAYED` and `SYS_OMAP4_HAS_DVFS_FRAMEWORK` and the `-include products.mk` that sets the debug options above (and `SGX_DISABLE_VISTEST_SUPPORT`). 4.4 also sets `is_at_least_icecream_sandwich_mr1` and `is_at_least_jellybean`, which only change `API_LEVEL` (14 to 16, in `platform_version.mk`) and settings in `features.mk` (`PVR_ANDROID_HAS_GRALLOC_USAGE_HW_VIDEO_ENCODER`, unit-test include paths, and `PVR_ANDROID_COMPOSITOR_WAIT_FOR_RENDER`, which `omap4430_android/Makefile` sets anyway). None of them is a `KernelConfigC`, `TunableKernelConfigC` or `BothConfigC` option, and no file of `eurasia_km` outside the makefiles names them, so the module is the same either way.
- XE24's user space: `libIMGegl_SGX540_120.so` and `libGLESv2_POWERVR_SGX540_120.so` carry `build 1.9@2166536`. `libsrv_um`, `libsrv_init` and `pvrsrvinit` carry no DDK version or build-option strings. `libsrv_um` carries `PVRSRV_ERROR_BUILD_MISMATCH` and `PVRSRV_ERROR_DDK_VERSION_MISMATCH`.
- Not decidable from strings: the SGX build-options word that user space (`pvrsrvinit`, through `libsrv_init`) and the module compare at start-up (`BUILD_MISMATCH`). The hardware check settles it: on a mismatch the module logs `(FAIL) SGXInit: Mismatch in client-side and KM driver build options` (`sgxinit.c`).
- `tuned` and `tuned-stable` modules differ from ours in `.text`, `.data` and `.bss` because of kernel config (no ftrace `__gnu_mcount_nc`, no spinlock debug `__rwlock_init`), not because of DDK options. `scripts/compare_ko.py` reports 90 CRC differences against the stock module for each, and two symbols the stock module imports (`__gnu_mcount_nc`, `__rwlock_init`) do not exist in them. Even a forced load (`CONFIG_MODULE_FORCE_LOAD=y`) would fail on those, so only our module loads into them.

## What it unlocks

Config changes that alter structures used by the module are possible, because the module is rebuilt with the kernel. Each such change must re-run `compare_ko.py` and expect CRC differences only where intended.

On `tuned-stable` (3.4.113), 59 of the module's 165 CRCs differ from `tuned`'s, with the same imported symbols: see [`stable-merge.md`](stable-merge.md#the-gpu-module-pvrsrvkm).

## Open items

- Test the module on hardware: see [`hardware-checks.md`](hardware-checks.md).
