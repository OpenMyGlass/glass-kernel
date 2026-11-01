# Model B energy policy (`modelb-power` kernel variant)

Model B is the plain-Linux (Alpine/musl) Glass OS. This document describes the
`modelb-power` kernel variant, which is the `modelb` plain-Linux kernel plus a
power-optimizing config overlay, and the userspace (glassd) hooks it exposes.

The kernel variant only makes the power machinery *available* and *armed*. The
large battery wins on a wearable are a matter of userspace **policy** -- suspending
when idle, powering radios down, dimming/blanking the display -- which glassd owns.
The sysfs/ioctl contract for that policy is specified in
[glassd hooks](#glassd-hooks) below. A separate agent owns glassd; nothing here
implements userspace.

## Variants and how they stack

    stock         Google's source + notle_defconfig, unchanged
    tuned         stock + configs/tuned.config + patches/tuned/
    tuned-stable  tuned, on the linux-3.4.y 3.4.113 merge
    modelb        tuned-stable + configs/modelb.config        (plain-Linux base)
    modelb-power  modelb + configs/modelb-power.config         (energy policy)

Build it in the container like any other variant:

    VARIANT=modelb-power scripts/build-in-container.sh

`configs/modelb.config` is the plain-Linux base (devtmpfs so a lean init needs no
`mdev` dance; VT + framebuffer console on the panel; the sysfs early-suspend
interface). `configs/modelb-power.config` is power-only and touches no display,
DSS, panel or FPGA option, so layering it cannot regress the `modelb` display or
firmware bring-up.

## What the kernel provides

Almost the entire OMAP4 power stack is already compiled into `notle_defconfig`.
`configs/modelb-power.config` pins it on (so a future `select` cannot silently drop
it) and turns on the few idle-power options that were off. Concretely:

| Area | Mechanism (config) | State |
| --- | --- | --- |
| CPU idle | OMAP4 cpuidle (`CPU_IDLE`, coupled C-states), menu governor, `CPU_PM`; MPU CSWR/OSWR/OFF | already on; off-mode armed at runtime via debugfs |
| Tickless | `NO_HZ`, `HIGH_RES_TIMERS`, **`RCU_FAST_NO_HZ`** | RCU_FAST_NO_HZ newly enabled (was off) |
| Suspend-to-RAM | `SUSPEND`, `SUSPEND_FREEZER`, `PM_SLEEP`, Android `WAKELOCK`/`USER_WAKELOCK`/`EARLYSUSPEND` | already on |
| Runtime PM | `PM_RUNTIME`, `USB_SUSPEND`, `MMC_UNSAFE_RESUME` | already on |
| Undervolt | SmartReflex/AVS (`POWER_AVS*`, `CLASS1_P5`, `CLASS3`) | already on, per-chip, automatic |
| cpufreq | interactive default + conservative/powersave govs | already on |
| Radios | `RFKILL`, `RFKILL_PM`, `RFKILL_GPIO`, `CFG80211_DEFAULT_PS` | already on |
| Thermal | `OMAP4_DUTY_CYCLE[_GOVERNOR]` (safety; thresholds unchanged) | already on |

**Important correction to the Model-B plan note.** This Google 3.4 tree predates
the mainline opportunistic-suspend interface: there is **no `CONFIG_PM_AUTOSLEEP`
and no `CONFIG_PM_WAKELOCKS`** (those landed in v3.5). Opportunistic suspend here is
the *Android* path -- `/sys/power/state` + `/sys/power/wake_lock`. Likewise, this
kernel has **no direct-filesystem firmware loader** (added upstream in v3.7): the
FPGA/Wi-Fi firmware still loads via the usermode-helper (udev/mdev) *or* must be
built in with `CONFIG_EXTRA_FIRMWARE`. `modelb` does **not** change the firmware
path; that is a separate `modelb` decision, out of scope for the power overlay.

## Expected savings

Baseline (measured off-charger on stock XE24, 2026-11-01, battery ~600 mAh, logger
holding a wakelock so the system never suspended):

- momentary idle (screen off, awake) **41 mA / 164 mW**
- median active **436 mA**, mean active **365 mA / 1459 mW**
- max (screen + sensors) **627 mA / 2509 mW**
- known active battery life ~1 h.

Because the baseline run **held a wakelock, true suspended standby was never
measured** -- it is lower than the 41 mA floor above. Savings by mechanism:

| Mechanism | How it saves | Expected effect | Confidence |
| --- | --- | --- | --- |
| Opportunistic suspend-to-RAM | screen-off + no wakelock -> MPU OFF, CORE retention, 32 kHz only | the dominant idle win: OMAP4 suspend is typically tens of mW vs the 164 mW idle-awake floor; could multiply standby life | **needs on-device measurement** (this is THE number to capture) |
| Radio off (rfkill) | Wi-Fi OFF by default; BT blockable; airplane mode kills both | removes radio idle draw entirely; associated-idle Wi-Fi on this class is ~20-40 mA | medium; measure Wi-Fi-off vs associated |
| Display blank + backlight | FBIOBLANK powers down panel + DSS when not looking | the panel/prism is the biggest active consumer; the 627 vs 436 mA gap is largely display + sensors | medium; measure blank vs on |
| cpufreq eco/cool + deep C-states | 89% residency at 300 MHz; low floor, conservative ramp; tickless + RCU_FAST_NO_HZ + MPU retention between frames | cuts active and idle-awake CPU power; SmartReflex already undervolts per chip | low-medium; measure governor A/B |

No single kernel option is the win; the win is suspend + radio-off + display-blank
policy on top of this kernel. All four rows need an off-charger A/B measurement
(the `tools/power-log.sh` / `battlog.sh` method from the device-tests note; current
goes negative off-charger). The safety rule stands: **no voltage/frequency/thermal
threshold changes** -- CPU savings come only from the governor profile and from
SmartReflex, which already undervolts automatically.

## glassd hooks

glassd (or a small power daemon) implements the policy through these interfaces.
All are standard sysfs/ioctl; none require a kernel change beyond this variant.
Paths marked *verify* were read on stock XE24 and should be re-confirmed on a
`modelb-power` boot, since node numbering can differ.

### 1. Opportunistic suspend (the big win)

This kernel uses the Android wakelock model, not `/sys/power/autosleep`.

- `/sys/power/wake_lock`   -- write `"<name>"` or `"<name> <timeout_ns>"` to take a
  named lock. Hold one (e.g. `glassd-active`) while there is work; the system will
  not suspend while any lock is held.
- `/sys/power/wake_unlock` -- write `"<name>"` to release it.
- `/sys/power/state`       -- write `mem` to request suspend-to-RAM. With the
  wakelock patch the suspend is **deferred until all locks are released**, so the
  typical flow is: on screen-off, release `glassd-active` and (once) write `mem`;
  on any input/timer/wakeup the resume path runs and glassd re-takes the lock.
  Writing `on` cancels a pending request.
- `/sys/power/wait_for_fb_sleep`, `/sys/power/wait_for_fb_wake` -- blocking reads
  (from `FB_EARLYSUSPEND`) that tell userspace when to stop/resume drawing.

Wake sources (what may resume the system) are the power button
(`twl6030_pwrbutton`), the touchpad, the BT HCI UART, and any device whose
`.../power/wakeup` is `enabled`. glassd should ensure only the intended wake
sources are enabled before writing `mem`.

### 2. Display brightness / blank

- Blank: `FBIOBLANK` ioctl on `/dev/fb0` with `FB_BLANK_POWERDOWN` (and
  `FB_BLANK_UNBLANK` to restore). This powers the panel + DSS pipeline down. glassd
  already does FBIOBLANK.
- Brightness: `/sys/devices/platform/omapdss/manager2/panel-notle-dpi/brightness`
  (*verify*; read 0 with the screen off on stock). Write a low value when dimming,
  0 to go dark without a full blank.

### 3. Radios (rfkill + runtime PM)

- Enumerate `/sys/class/rfkill/rfkillN/` (`name`, `type` = `wlan`/`bluetooth`).
- Block: write `1` to `.../soft` (or `rfkill block wlan|bluetooth`); unblock with
  `0`. A fully blocked radio is powered down with no leakage (that is the point of
  `RFKILL_PM` + `RFKILL_GPIO`).
- **Airplane mode** = block every rfkill at once (`rfkill block all`). GPS is
  already off at `/sys/class/gps/gps_elton/onoff` (set `0`).
- Default policy: Wi-Fi (bcmdhd, SDIO) **OFF**; BT (bcm4330 on the `/dev/ttyO1` HCI
  UART) is the main link, brought up only when needed and parked otherwise.
- Wi-Fi power-save is on by default (`CFG80211_DEFAULT_PS`) when it is up.

### 4. cpufreq profile

Use `tuning/omg-tune.sh` (already in the repo). For Model B at rest pick a
power-leaning profile:

- `omg-tune.sh eco`   -- cap 600 MHz (lightest)
- `omg-tune.sh cool`  -- cap 800 MHz (verified on hardware to hold the cap)

Paths: `/sys/devices/system/cpu/cpu0/cpufreq/` and
`/sys/devices/system/cpu/cpufreq/interactive/`. glassd should apply the chosen
profile at boot (nothing is persistent across reboot) and may raise it transiently
for heavy work.

### 5. Peripheral runtime PM (autosuspend)

For USB, MMC, I2C and sensor devices, set runtime PM to auto so idle devices power
down:

- `.../power/control` = `auto`  (per device under `/sys/bus/{usb,i2c,mmc,platform}/devices/*/`)
- `.../power/autosuspend_delay_ms` = a small delay where supported.

Sensors that stream (IMU in IIO buffer mode, light/proximity) should be disabled by
glassd when no client needs them, otherwise they hold the SoC out of deep idle.

## Risk to the display / firmware bring-up

`configs/modelb-power.config` is power-only: it changes **no** DSS, `omapfb`,
`panel-notle-dpi`, backlight or FPGA option. By construction it cannot regress the
display or firmware bring-up.

`configs/modelb.config` adds fbcon, which needs `CONFIG_VT`. fbcon attaches to the
framebuffer `omapfb` already creates; it does not change how the panel or iCE40 FPGA
come up. The one interaction to watch is the early-suspend "user-space screen
access" choice: enabling VT would otherwise flip its default to
`CONSOLE_EARLYSUSPEND` (which switches VTs on blank); `modelb.config` pins
`FB_EARLYSUSPEND` instead, matching what `notle_defconfig` selected before VT
existed and keeping the `/sys/power/wait_for_fb_*` sysfs that glassd uses. All of
this is validated at build time: the build fails if Kconfig drops any requested
option.

Open items for on-device validation: (1) the suspended standby current (the key
missing number); (2) fbcon rendering on the panel without disturbing the glassd
display path; (3) that writing `mem` with no wakelock actually reaches
suspend-to-RAM and resumes on power-button/touchpad on this exact kernel.
