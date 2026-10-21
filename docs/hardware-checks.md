# Hardware checks

## Read-only checks (stock kernel running; nothing is booted or flashed)

1. Confirm the device runs XE24: Settings → Device info, or `adb shell getprop ro.build.fingerprint`.
2. Kernel version and build string: `adb shell cat /proc/version`. Expected: `Linux version 3.4.94…`.
3. Factory kernel configuration, if exposed: `adb shell zcat /proc/config.gz > factory-config` (`adb shell cat /proc/config.gz | gunzip` on older adb). Compare it with `out/config` from CI using `scripts/diffconfig` from the kernel tree (`src/scripts/diffconfig factory-config out/config`).
4. Record the result in an issue: same version and an empty or tiny diff confirms that `glass-omap-xrx13b` is the XE24 source. A large diff means picking another `glass-omap-*` branch.

## After the first `fastboot boot` of our kernel (RAM only)

Only with the owner present. `fastboot boot` runs from RAM and writes nothing to the device. These steps check the GPU module.

XE24's `init.omap4430.rc` runs `insmod /system/lib/modules/pvrsrvkm_sgx540_120.ko` in `on fs` and then starts `service pvrsrvinit /vendor/bin/pvrsrvinit`. Because the kernel is built with `CONFIG_MODVERSIONS`, it ignores the `LOCALVERSION` part of vermagic and all 167 CRCs match, so the stock module would most likely load into our kernel. Booting without further steps would therefore test the stock module, not ours.

To test ours:

1. Put `out/pvrsrvkm_sgx540_120.ko` in the boot ramdisk (for example `/pvrsrvkm_sgx540_120.ko`) and load it with `insmod` from an init step that runs before `on fs`, for example `on early-fs`. The stock `insmod` in `on fs` then fails with `EEXIST`, which is harmless. Adding the `.ko` to the ramdisk is a follow-up in glass-rom; it is not done yet.
2. Check that the loaded module is ours. On the host, `modinfo -F srcversion out/pvrsrvkm_sgx540_120.ko` and `modinfo -F srcversion <stock .ko>` give two values. On the device, `adb shell cat /sys/module/pvrsrvkm_sgx540_120/srcversion` must equal the one from our build and differ from the stock one. If the two host values turn out equal, use `adb shell dmesg | grep -n -e pvrsrvkm -e insmod` instead: the first successful load must come from the early-fs step and the later one from `on fs` must report `File exists`.
3. `adb shell dmesg`: there must be no `PVRSRV_ERROR_DDK_VERSION_MISMATCH` and no `BUILD_MISMATCH` after `pvrsrvinit` runs.
4. Check that SurfaceFlinger starts (`adb shell ps | grep surfaceflinger`, and the display works).
