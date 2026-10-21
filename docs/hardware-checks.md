# Hardware checks

## Read-only checks (stock kernel running; nothing is booted or flashed)

1. Confirm the device runs XE24: Settings → Device info, or `adb shell getprop ro.build.fingerprint`.
2. Kernel version and build string: `adb shell cat /proc/version`. Expected: `Linux version 3.4.94…`.
3. Factory kernel configuration, if exposed: `adb shell zcat /proc/config.gz > factory-config` (`adb shell cat /proc/config.gz | gunzip` on older adb). Compare it with `out/config` from CI using `scripts/diffconfig` from the kernel tree (`src/scripts/diffconfig factory-config out/config`).
4. Record the result in an issue: same version and an empty or tiny diff confirms that `glass-omap-xrx13b` is the XE24 source. A large diff means picking another `glass-omap-*` branch.

## After the first `fastboot boot` of our kernel (RAM only)

Only with the owner present. `fastboot boot` runs from RAM and writes nothing to the device. These steps check the GPU module.

XE24's `init.omap4430.rc` runs `insmod /system/lib/modules/pvrsrvkm_sgx540_120.ko` in `on fs` and then starts `service pvrsrvinit /vendor/bin/pvrsrvinit`. Because the kernel is built with `CONFIG_MODVERSIONS`, it ignores the `LOCALVERSION` part of vermagic and all 167 CRCs match, so the stock module would most likely load into our kernel. Booting without further steps would therefore test the stock module, not ours.

To test ours, the stock module must never be loaded:

1. The boot image we `fastboot boot` carries its own ramdisk, which contains `init.omap4430.rc`. In that ramdisk copy, change the `on fs` line `insmod /system/lib/modules/pvrsrvkm_sgx540_120.ko` to load our module from the ramdisk instead, for example `insmod /lib/modules/pvrsrvkm_sgx540_120.ko`, and put `out/pvrsrvkm_sgx540_120.ko` at that path in the ramdisk. Doing this in glass-rom is a follow-up; it is not done yet. Nothing is written to the device.
2. Check that the module is ours:
   - (a) On the host, before booting: the boot image's ramdisk `init.omap4430.rc` contains no `/system/lib/modules/pvrsrvkm` line (for example `grep -c /system/lib/modules/pvrsrvkm init.omap4430.rc` prints `0`).
   - (b) On the device: `adb shell cat /proc/modules` lists `pvrsrvkm_sgx540_120`.
3. `adb shell dmesg`: there must be no `PVRSRV_ERROR_DDK_VERSION_MISMATCH` and no `BUILD_MISMATCH` after `pvrsrvinit` runs.
4. Check that SurfaceFlinger starts (`adb shell ps | grep surfaceflinger`, and the display works).
