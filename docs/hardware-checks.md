# Hardware checks (before any boot test)

These steps only read from the device: nothing is flashed and nothing is booted.

1. Confirm the device runs XE24: Settings → Device info, or `adb shell getprop ro.build.fingerprint`.
2. Kernel version and build string: `adb shell cat /proc/version`. Expected: `Linux version 3.4.94…`.
3. Factory kernel configuration, if exposed: `adb shell zcat /proc/config.gz > factory-config` (`adb shell cat /proc/config.gz | gunzip` on older adb). Compare it with `out/config` from CI using `scripts/diffconfig` from the kernel tree (`src/scripts/diffconfig factory-config out/config`).
4. Record the result in an issue: same version and an empty or tiny diff confirms that `glass-omap-xrx13b` is the XE24 source. A large diff means picking another `glass-omap-*` branch.

Booting our kernel comes in a later phase, with `fastboot boot` only (RAM, nothing written) and with the owner present.
