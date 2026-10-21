# Hardware checks

## Read-only checks (stock kernel running; nothing is booted or flashed)

1. Confirm the device runs XE24: Settings → Device info, or `adb shell getprop ro.build.fingerprint`.
2. Kernel version and build string: `adb shell cat /proc/version`. Expected: `Linux version 3.4.94…`.
3. Factory kernel configuration, if exposed: `adb shell zcat /proc/config.gz > factory-config` (`adb shell cat /proc/config.gz | gunzip` on older adb). Compare it with `out/config` from CI using `scripts/diffconfig` from the kernel tree (`src/scripts/diffconfig factory-config out/config`).
4. Record the result in an issue: same version and an empty or tiny diff confirms that `glass-omap-xrx13b` is the XE24 source. A large diff means picking another `glass-omap-*` branch.

## After the first `fastboot boot` of our kernel (RAM only)

Only with the owner present. `fastboot boot` runs from RAM and writes nothing to the device. These steps check the GPU module.

XE24's `init.omap4430.rc` runs `insmod /system/lib/modules/pvrsrvkm_sgx540_120.ko` in `on fs` and then starts `service pvrsrvinit /vendor/bin/pvrsrvinit`. Because the kernel is built with `CONFIG_MODVERSIONS`, it does not compare the kernel release part of vermagic (it checks the symbol CRCs instead). On the `stock` variant all 167 CRCs match, so the stock module would most likely load into it, and booting without further steps would test the stock module, not ours. On `tuned` and `tuned-stable`, 90 CRCs differ and two symbols it imports (`__gnu_mcount_nc`, `__rwlock_init`) are missing, so the stock module cannot load at all.

To test ours, the stock module must never be loaded:

1. The boot image we `fastboot boot` carries its own ramdisk, which contains `init.omap4430.rc`. Build it with glass-rom (`make_insecure_boot.py --pvr-module`, from OpenMyGlass/glass-rom#16) from the owner's `boot.img` and the `zImage` and `pvrsrvkm_sgx540_120.ko` of the same CI artifact: `tools/make_insecure_boot.py factory/boot.img out/boot-test.img --kernel zImage --pvr-module pvrsrvkm_sgx540_120.ko`. It puts our module at `/lib/modules/pvrsrvkm_sgx540_120.ko` in the ramdisk and changes the `on fs` line `insmod /system/lib/modules/pvrsrvkm_sgx540_120.ko` to `insmod /lib/modules/pvrsrvkm_sgx540_120.ko`. Nothing is written to the device.
2. Check that the module is ours:
   - (a) On the host, before booting: the boot image's ramdisk `init.omap4430.rc` contains no `/system/lib/modules/pvrsrvkm` line (for example `grep -c /system/lib/modules/pvrsrvkm init.omap4430.rc` prints `0`).
   - (b) On the device: `adb shell cat /proc/modules` lists `pvrsrvkm_sgx540_120`.
3. `adb shell dmesg | grep SGXInit`: after `pvrsrvinit` runs there must be no `(FAIL)` line, such as `(FAIL) SGXInit: Mismatch in client-side and KM driver build options` or `(FAIL) SGXInit: Incompatible driver DDK revision` (the messages behind `PVRSRV_ERROR_BUILD_MISMATCH` and `PVRSRV_ERROR_DDK_VERSION_MISMATCH`).
4. Check that SurfaceFlinger starts (`adb shell ps | grep surfaceflinger`, and the display works).

## `tuned-stable` (3.4.113) boot checks — NOT RUN

None of these has been run: no Glass is available. Only with the owner present, only with `fastboot boot` (RAM only, nothing written), and only after `tuned` has booted and passed the checks above, so that a failure points at the stable merge. A reboot returns to the stock kernel. Compare every result with the same check on `tuned`.

1. **Version:** `adb shell cat /proc/version` shows `Linux version 3.4.113-gb6ea856-dirty…` (`-dirty` because the tuned patches are applied to the checkout).
2. **GPU module:** the stock XE24 module does not load into this kernel: 59 CRCs of its imports differ even from `tuned`'s (see [`stable-merge.md`](stable-merge.md#the-gpu-module-pvrsrvkm)), so `insmod` fails with `disagrees about version of symbol`. So the boot image's ramdisk must load `pvrsrvkm_sgx540_120.ko` from the `kernel-tuned-stable` artifact, built with glass-rom's `--pvr-module` as described in the GPU module steps above. Then run those steps 2–4.
3. **Pin muxing:** `adb shell dmesg | grep -iE 'multiple signal paths|could not set signal|mux'` gives the same lines as on `tuned` (upstream ba8f03aa changed pin-name matching; a static check found no effect on notle).
4. **Watchdog:** the device stays up for at least 15 minutes with the screen on and with the screen off, with no reset (upstream dd7ad96c changed `omap_wdt_open()`). After any reset, read `/proc/last_kmsg` from the stock kernel.
5. **Suspend and resume:** turn the screen off for 5 minutes, then wake it. `adb shell cat /sys/kernel/debug/suspend_stats` shows more successes and no new failures, and `dmesg` has no freezer errors (upstream 0629784c changed the CPU suspend path, and a2ca02f1 and 7655f855 changed how OOM-killed tasks are frozen).
6. **Thermal:** `adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state` read twice, 10 minutes apart under a steady load, shows the same duty-cycle pattern as on `tuned` (stable changes no thermal code; this checks that nothing else interferes).
7. **Radios and storage:** Wi-Fi connects, Bluetooth pairs with the phone and stays connected for 10 minutes (stable changes the Bluetooth core), and `dmesg` has no `EXT4-fs error` and no `mmc` errors.
8. **USB:** `adb` keeps working over a replug. `/sys/class/switch/usb_audio/state` exists (the `sound/usb/card.c` conflict kept it).

If any check fails, record `dmesg`, `logcat` and the failing check in an issue, and go back to the stock kernel with a reboot.

## Touchpad input boost (`tuned`, `tuned-stable`) — NOT RUN

None of these has been run: no Glass is available. Only with the owner present, only with `fastboot boot` (RAM only, nothing written), after the boot and GPU module checks above pass on the same kernel. A reboot returns to the stock kernel. The knob is described in [`tuning.md`](tuning.md#touchpad-input-boost-patchestuned00060008).

1. **Connected to the touchpad:** `adb shell dmesg | grep cpufreq_interactive_input_connect` shows `connect to sensor00fn11`, once. Record any other device it connects to.
2. **Default:** `adb shell cat /sys/devices/system/cpu/cpufreq/interactive/input_boost` prints `1`, and `adb shell sh /data/local/tmp/omg-tune.sh status` lists `input_boost: 1`.
3. **It fires on touch, and only then:** with tracing (`echo 1 > /sys/kernel/debug/tracing/events/cpufreq_interactive/cpufreq_interactive_boost/enable`, then `cat /sys/kernel/debug/tracing/trace_pipe`), swiping gives `cpufreq_interactive_boost: input` lines, and there are none, or only occasional ones, with the finger off the touchpad for 30 s (the F11 driver also reports a cover switch, `SW_CAMERA_LENS_COVER`, and each of its reports ends with `SYN_REPORT` too; record how many). Turn the event off afterwards.
4. **The knob turns it off:** `omg-tune.sh input-boost off`; swiping gives no more `input` lines; `input-boost on` brings them back.
5. **Frequency stays bounded:** while swiping, `scaling_cur_freq` never exceeds `scaling_max_freq` or `hispeed_freq`, also after `omg-tune.sh cool` (800 MHz hispeed and max).
6. **Effect:** `cpu0/cpufreq/stats/time_in_state` read before and after 30 s of steady swiping through cards, once with `input_boost` 1 and once with 0: the time at `hispeed_freq` grows with 1. Note any visible difference in how quickly the cards respond.
7. **Already boosted by the system?** With `input_boost` 0, trace `cpufreq_interactive_boost` while swiping: `pulse` lines mean XE24's power HAL already writes `boostpulse` on touch, and the kernel boost then mostly duplicates it. Record which.
8. **Suspend:** screen off for 5 minutes, then wake with a tap: the touchpad still works and `dmesg` has no `cpufreq_interactive` or `rmi` errors.

## `hispeed_freq` ceiling (`tuned`, `tuned-stable`; `0009`) — NOT RUN

None of these has been run: no Glass is available. Only with the owner present, only with `fastboot boot` (RAM only, nothing written), after the boot checks above pass on the same kernel. A reboot returns to the stock kernel and its defaults. Background in [`tuning.md`](tuning.md#hispeed_freq-as-a-ceiling-patchestuned0009). The test writes only governor tunables, all below the stock values, never above 1008 MHz.

1. **Before (stock kernel, read-only):** on stock XE24, `omg-tune.sh status` after boot and after a screen off/on cycle. Record `hispeed_freq` and `scaling_max_freq`: if the system writes a `hispeed_freq` below the maximum, stock XE24 itself is affected by the drop to the lowest speed.
2. **Clamp:** on the `tuned` kernel, `echo 600000 > /sys/devices/system/cpu/cpufreq/interactive/hispeed_freq` (keep `scaling_max_freq` at 1008000), then run a steady CPU load on both cores (for example two `adb shell 'while :; do :; done' &`) for 30 s. `scaling_cur_freq`, read every second, stays at 600000; `time_in_state` grows at 600 MHz, not at 300 MHz and not above 600 MHz. Stop the load and write `hispeed_freq` back to 1008000 (or reboot).
3. **For comparison, the stock build** (only if the owner wants to see the bug): the same steps on the `stock` kernel show `scaling_cur_freq` falling to 300000 under the load. This is the stock behaviour, run only from RAM.
4. **Profiles:** after `omg-tune.sh cool`, `status` shows `hispeed_freq: 800000` and `scaling_max_freq: 800000`; after `omg-tune.sh stock`, both are 1008000.

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
