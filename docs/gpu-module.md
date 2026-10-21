# GPU module (pvrsrvkm)

The SGX540 driver, `pvrsrvkm_sgx540_120.ko`, is built from source together with the kernel. `scripts/build.sh` writes it to `out/`.

## Which DDK, and why

- **Source:** KFire-Android/android_vendor_amazon_otter @ `7d7692662a6d906fe074475602ae3085aa4e35cd`, directory `proprietary/imgtec/eurasia_km` ("IMG DDK 1.9@2166536 for Android"). Its README gives a MIT/GPL-2.0 dual licence. Pinned in `scripts/source.env`, fetched by `scripts/fetch-pvr.sh`.
- **Why this one:** XE24's user-space libraries are DDK `1.9@2166536` (`libIMGegl` and `libGLESv2` carry "build 1.9@2166536"), and the DDK checks versions between user space and kernel (`PVRSRV_ERROR_DDK_VERSION_MISMATCH`).
- **Not used:** OMAP4-AOSP `pvr-source` is DDK `1.9@2291151`. Using it would need user-space libraries from another device.

## How it is built

After the kernel (`zImage`, `modules_prepare`), `scripts/build.sh` copies the DDK to `out/pvr-build` and runs the DDK's `omap4430_android` makefiles against the kernel build directory. The exact variables are in `scripts/build.sh`. `PLATFORM_VERSION=4.0` selects ICS-era DDK options that are not yet checked against the stock module's build options (see Open items).

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

## What it unlocks

Config changes that alter structures used by the module are possible, because the module is rebuilt with the kernel. Each such change must re-run `compare_ko.py` and expect CRC differences only where intended.

## Open items

- Compare the DDK build options of the stock module with ours (offline). `PLATFORM_VERSION=4.0` in `scripts/build.sh` selects ICS-era options that are not yet checked.
- Test the module on hardware: see [`hardware-checks.md`](hardware-checks.md).
