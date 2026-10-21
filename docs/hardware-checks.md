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

## `tuned-stable` (3.4.113) boot checks — NOT RUN

None of these has been run: no Glass is available. Only with the owner present, only with `fastboot boot` (RAM only, nothing written), and only after `tuned` has booted and passed the checks above, so that a failure points at the stable merge. A reboot returns to the stock kernel. Compare every result with the same check on `tuned`.

1. **Version:** `adb shell cat /proc/version` shows `Linux version 3.4.113-gb6ea856…`.
2. **GPU module:** the stock XE24 module does not load into this kernel: 59 CRCs of its imports differ even from `tuned`'s (see [`stable-merge.md`](stable-merge.md#the-gpu-module-pvrsrvkm)), so `insmod` fails with `disagrees about version of symbol`. So the boot image's ramdisk must load `out/pvrsrvkm_sgx540_120.ko` from the `kernel-tuned-stable` artifact, as described in the GPU module steps above. Then run those steps 2–4.
3. **Pin muxing:** `adb shell dmesg | grep -iE 'multiple signal paths|could not set signal|mux'` gives the same lines as on `tuned` (upstream ba8f03aa changed pin-name matching; a static check found no effect on notle).
4. **Watchdog:** the device stays up for at least 15 minutes with the screen on and with the screen off, with no reset (upstream dd7ad96c changed `omap_wdt_open()`). After any reset, read `/proc/last_kmsg` from the stock kernel.
5. **Suspend and resume:** turn the screen off for 5 minutes, then wake it. `adb shell cat /sys/kernel/debug/suspend_stats` shows more successes and no new failures, and `dmesg` has no freezer errors.
6. **Thermal:** `adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state` read twice, 10 minutes apart under a steady load, shows the same duty-cycle pattern as on `tuned` (stable changes no thermal code; this checks that nothing else interferes).
7. **Radios and storage:** Wi-Fi connects, Bluetooth pairs with the phone and stays connected for 10 minutes (stable changes the Bluetooth core), and `dmesg` has no `EXT4-fs error` and no `mmc` errors.
8. **USB:** `adb` keeps working over a replug. `/sys/class/switch/usb_audio/state` exists (the `sound/usb/card.c` conflict kept it).

If any check fails, record `dmesg`, `logcat` and the failing check in an issue, and go back to the stock kernel with a reboot.

## Debugging a boot with a normal USB cable

No extra hardware is needed: everything below uses the micro-USB cable and `fastboot`/`adb`.

1. **The log of a failed boot, `/proc/last_kmsg`.** The kernel is built with `CONFIG_ANDROID_RAM_CONSOLE` (with `CONFIG_OMAP_RAM_CONSOLE`): its log is kept in a RAM area that survives a warm reset. After a test kernel hangs, panics or resets, boot the stock kernel and read `adb shell cat /proc/last_kmsg`. It holds the failed boot's log from its first line. First check on a known-good boot that the bootloader keeps that RAM across a warm reset: `adb reboot`, then `/proc/last_kmsg` must show the previous boot.
2. **Live, once the system is up:** `adb shell dmesg` for the kernel and `adb logcat` for Android.
3. **A USB serial port without an adapter.** The Android USB gadget has an `acm` function, which shows up on the host as `/dev/tty.usbmodem*` (macOS) or `/dev/ttyACM*` (Linux).
   - On 3.4 it cannot be the kernel console.
   - An init step in the test boot image's ramdisk can still copy `/proc/kmsg` to `/dev/ttyGS0`, or start a shell on it.
   - Read it with `screen <port> 115200`.
   - It works only once the USB gadget driver is up, so the first seconds of boot come from `last_kmsg`.
4. **Mainline equivalents:** `ramoops` (pstore) with a RAM area reserved in the device tree, in place of `last_kmsg`, and a real kernel console over USB, `console=ttyGS0` (`CONFIG_U_SERIAL_CONSOLE`).

Last resort, only if a kernel stops before any of the above can capture something:
- **The connector can carry a UART.** Glass's micro-USB data lines go through an analog switch (`arch/arm/mach-omap2/notle-usb-mux.c`) with `usb`, `tty`, `audio` and `floating` modes.
  - The kernel selects `tty` when no USB host is attached and `usb_mux.tty_priority=1` is on the kernel command line. The console is `console=ttyO2,115200n8`.
  - This needs a special cable: D+/D− to a USB-serial adapter, ground, and **no VBUS**, because VBUS makes the kernel switch back to `usb`.
  - The OMAP's UART runs at 1.8 V logic (unverified), so the adapter must be a 1.8 V one. Which line is TX is unknown: connect the adapter's RX first.
  - The mux is switched only when its driver probes, so the earliest boot messages are not on the wire.
- **Factory cable:** an ID-pin voltage above 4.2 V makes the kernel reboot into the bootloader, unless the command line has `androidboot.mode=factorycable`.
