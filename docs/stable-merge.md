# The linux-3.4.y stable merge (3.4.113)

The `tuned-stable` variant builds Google's Glass kernel merged with the last linux-3.4.y stable release, 3.4.113 (2016-10-26). Nothing here has run on hardware. The plan, with the options weighed, is [`plans/2026-10-21-phase-5-stable-3.4.113.md`](plans/2026-10-21-phase-5-stable-3.4.113.md).

## What was merged

| | |
|---|---|
| Ours (first parent) | `kernel/omap` `glass-omap-xrx13b` @ `989d925476700c0d07a75008b37725cbc558f862` (3.4.94) |
| Theirs (second parent) | tag `v3.4.113` (PGP-signed by Zefan Li) @ `8d1988f838a95e836342b505398d38b223181f17`, from `git.kernel.org/…/stable/linux.git` |
| Merge base | `v3.4.94` @ `95f3bb9bd690350d1ba58cb1541a26ce2db209e8`, which Google merged in `4e256f0731` ("Merge tag 'v3.4.94' into kernel"). Erratum: the merge commit's message abbreviates this as `4e256f07ce`, which is wrong after the eighth digit; the branch is frozen, so the message stays |
| Upstream commits | 1450 (3.4.95 to 3.4.113, 19 releases), none of them merges |
| Result | [`OpenMyGlass/kernel-omap`](https://github.com/OpenMyGlass/kernel-omap) branch `glass-omap-xrx13b-stable-3.4.113` @ `b6ea8564759ba36c96db4a07e2f5647c890c3f86`, tree `c8dc0475b38a50e1965ce3bc280225356f9a404f` |
| Change against Google's tree | 1178 files, +14,668 / −7,017 lines |

The merge is one commit. Every upstream commit is in its history unchanged, with its own author, message and SHA. `kernel-omap` also has `glass-omap-xrx13b`, an unchanged mirror of Google's branch at the pinned commit. All branches there are frozen (no update, no deletion, no force-push): a later merge gets a new branch, so the pins in `scripts/source.env` keep working.

## Checking it

`scripts/check-stable-merge.sh` (needs git 2.38 or newer and about 100 MB; CI job `stable-merge`):
1. fetches the two inputs (history from 2014 on) and the pinned merge;
2. checks the pins, the merge base and the merge's two parents;
3. runs git's own merge (`git merge-tree --write-tree`, merge-ort) and checks that exactly the five files below conflict;
4. applies [`stable-merge/v3.4.113-resolutions.patch`](../stable-merge/v3.4.113-resolutions.patch) and the dwc3 decision to git's result;
5. checks that the result is the pinned commit's tree.

So the merge contains nothing beyond git's automatic merge and the resolutions listed here.

## Conflicts

git merges 5 files with conflicts. Each was resolved by hand:

| File | Built on notle | Why it conflicts | Resolution (side kept) |
|---|---|---|---|
| `net/netfilter/xt_socket.c` | yes (`NETFILTER_XT_MATCH_SOCKET=y`) | Android turned the IPv6 match into `xt_socket_get6_sk()`, which returns `struct sock *` (for qtaguid). Stable's cea9eddd ("netfilter: xt_socket: fix a stack corruption bug") adds an `&ipv6_var` argument to the `extract_icmp6_fields()` call that Android changed. | **Both.** Stable's new argument, and Android's `return NULL` (stable's `return false` belongs to the old `bool` function). `ipv6_var` is a local of `xt_socket_get6_sk()`, which is also where the addresses are used, so the fix holds. |
| `sound/usb/card.c` | yes (`SND_USB_AUDIO=y`) | Android added a `usb_audio` switch device and calls `switch_set_state(&sdev, STATE_DISCONNECTED)` in `snd_usb_audio_disconnect()`. Stable's 7ef2f8d1 ("ALSA: usb-audio: Fix device_del() sysfs warnings at disconnect") restructures that function. | **Both.** Stable's structure (`if (!was_shutdown)`, then the interface count), and Android's `switch_set_state()` at the same point, so it still runs on every interface disconnect as before. |
| `drivers/usb/dwc3/core.c` | no | see below | **Google's file, whole** |
| `drivers/usb/dwc3/ep0.c` | no | | **Google's file, whole** |
| `drivers/usb/dwc3/gadget.c` | no | | **Google's file, whole** |

dwc3: TI's tree carries a dwc3 driver backported from later mainline for OMAP5 (for example `dep->endpoint.desc` instead of `dep->desc`, and `usb_phy` handling), so stable's ten 3.4 dwc3 fixes do not fit it. The driver is not built for notle (`# CONFIG_USB_DWC3 is not set`), and the OMAP4430 has no DWC3 controller, so a port could not be compiled or tested here. `core.h` and `gadget.h` merged cleanly but are kept as Google's too, so the driver stays consistent. The stable dwc3 commits not taken: 4cbd8a25, 93408be9, 0169c97f, 72c2bc68, e82160b7, 272bc28a, 15488de7, 0552a3c9, 44b2ffc5 (reverts 0552a3c9), f43d490b.

Cross-check: the two hand-resolved files are byte-identical to the same files in Unlegacy-Android's independent 3.4.113 merges of TI's OMAP4 tree (`android_kernel_ti_omap4`, `3.4/common` for `xt_socket.c`, `3.4/espresso` for `card.c`). invisiblek's Glass merge stops at 3.4.105, before both fixes.

## Glass-specific code

No conflict touches Glass-specific code, and stable changes none of these files: `arch/arm/mach-omap2/board-notle*.c`, `notle-usb-mux.c`, `omap_ram_console.c`, `drivers/staging/android/ram_console.c`, `drivers/staging/thermal_framework/` (duty-cycle governor, PCB sensor), `drivers/cpufreq/cpufreq_interactive.c`, `drivers/input/misc/glasshub.c`, `drivers/video/omap2/displays/panel-notle-dpi.c`. The `patches/tuned/` interactive-governor patches apply unchanged.

## The clean merges

A clean merge can still be wrong when Google already carries a fix that stable also brings, because it could end up applied twice. Two checks:
- **The same change.** Google's side and stable both change 67 files, and git merges 62 of them cleanly. In git's result, for 61 of those 62, the lines the merge changes in Google's file are exactly the lines stable changes in v3.4.94 (compared as sorted sets of `+`/`−` lines). The one exception is `fs/ext4/mballoc.c`, below. Two of the 61, `drivers/usb/dwc3/core.h` and `gadget.h`, are then set back to Google's version by the dwc3 decision above.
- **Fixes already in Google's tree.** Google's 4,625 non-merge commits that are not in v3.4.94 (full history, from a treeless clone: `git fetch --filter=tree:0 https://android.googlesource.com/kernel/omap refs/heads/glass-omap-xrx13b`, then `git log --no-merges glass-omap-xrx13b ^95f3bb9`) were matched against the 1450 stable commits, by upstream SHA (`cherry picked from commit …` against `commit … upstream`) and by subject. One is in both: b5b60778 "ext4: fix wrong assert in ext4_mb_normalize_request()" (Google's d20798d1, stable's 2dbc65d6). It is the same one-line change on both sides, so git merges it once.

## Upstream changes in power, thermal and charging code

No stable commit changes a voltage, OPP, thermal limit, charger current or fuel-gauge parameter. Stable does not touch `drivers/thermal`, `drivers/staging/thermal_framework`, the OMAP4 OPP, voltage, SmartReflex or clock data, the TWL6030 or BQ drivers, or `drivers/staging/android`. The stable commits in power-related code:

| Commit | Change | On notle |
|---|---|---|
| 8f108b36 regulator: core: fix race condition in regulator_put() | takes `rdev->mutex` around the list removal | built; locking only, no value changes |
| 0e782ba3 regulator: core: fix constraints output buffer | 80 → 160 byte buffer for the constraints log line | built; logging only |
| aea44610 cpufreq: expose scaling_cur_freq sysfs file for set_policy() drivers | `scaling_cur_freq` exists for every driver | built; omap-cpufreq is a `target` driver, so nothing changes |
| 73cee5a8 cpufreq: speedstep-smi | x86 | not built |
| 9fa2377f power: charger-manager: Fix NULL pointer exception with missing cm-fuel-gauge | charger-manager | not built (`# CONFIG_CHARGER_MANAGER is not set`) |
| 7c3bbea9 wm831x_power: Use IRQF_ONESHOT | WM831x PMIC | not built |
| 9de18f8e mfd: tc6393xb | another SoC | not built |
| 358105b8 PM / Sleep: fix recovery during resuming from hibernation | hibernation | not built (no `HIBERNATION`) |
| 7655f855 OOM, PM: OOM killed task shouldn't escape PM suspend | the freezer no longer lets an OOM-killed task run during suspend | built; affects suspend entry when the OOM killer has just run |
| 5dc1c885 PM / sleep: Fix request_firmware() error at resume | firmware loading right after resume | built |
| dd7ad96c watchdog: omap: assert the counter being stopped before reprogramming | `omap_wdt_open()` stops the watchdog before setting it up | built (`OMAP_WATCHDOG=y`); the timeout value is unchanged |
| ba8f03aa ARM: OMAP2+: Fix parser-bug in platform muxing code | a `mode0.mode` pin name must match the mode0 name exactly, not as a prefix | built; **checked, no effect on notle**: none of the 1143 pin names used in `arch/arm/mach-omap2` resolves differently on OMAP4 (32 mode0 names are prefixes of others, such as `gpmc_ad1`/`gpmc_ad10`, but none of them is used ambiguously) |
| 0629784c ARM: 8471/1: need to save/restore arm register(r11) when it is corrupted | `cpu_v7_do_suspend` in `arch/arm/mm/proc-v7.S` saves and restores r11 | built; OMAP4 runs it on every suspend and every deep cpuidle entry (`cpu_suspend()` in `omap-mpuss-lowpower.c`); register save only, no value changes |
| a2ca02f1 freezer: Do not freeze tasks killed by OOM killer | a task with `TIF_MEMDIE` is not frozen | built; Android's lowmemorykiller sets `TIF_MEMDIE` on its victims, so they can now exit during suspend entry instead of blocking it |
| 5624bb35, 3efcfa54, c2e9312c, b2e30785, 31a52644 | ARM core: abort handlers keep the exclusive monitors, NEON alignment fixup, `ELF_ET_DYN_BASE` overflow, Thumb IT state in signal handling | built; no power-related values |
| 8c095d35, b81cc21d, f8cce9e3, 3f6d9b62, fbbb7208, 3f8f4ae4; alarmtimer e0650342, b114657d, 7ccf24be, 299e667e | timekeeping, NTP, hrtimer, nohz and alarm-timer fixes | built; alarm timers wake Android from suspend |

The other upstream changes are in the core kernel (mm, scheduler, filesystems, networking, crypto, ALSA, USB, Bluetooth) and in drivers not built for notle.

## The GPU module (pvrsrvkm)

The DDK 1.9@2166536 module builds against `tuned-stable` with no change to the DDK. It was compared with `scripts/compare_ko.py`, using the modules from CI run 39671222156:

| Compared | Imported symbols | CRCs that differ | vermagic |
|---|---|---|---|
| `tuned` module against `tuned-stable` module | the same 164 | 59 of 165 (including `module_layout`) | `3.4.113-gb6ea856-dirty …` (the `-dirty` comes from the tuned patches applied to the checkout) |
| stock XE24 module against `tuned-stable` module | 166 and 164 (the stock module also imports `__gnu_mcount_nc` and `__rwlock_init`, which the `tuned` config already drops) | 90 of the 165 they share (also 90 against `tuned`, because of the lock-debugging config changes in phase 4) | as above |

No symbol the module imports is missing, so the module links and loads against its own kernel. The CRCs change because upstream stable changed the layout of core structures that genksyms folds into every symbol whose signature reaches them:
- `struct task_struct`: new `thread_head` and `thread_node` (b71ec075 "introduce for_each_thread() to replace the buggy while_each_thread()") and `atomic_flags` (699c06b3 "sched: add macros to define bitops for task atomic flags");
- `struct file` loses `fu_list` and `f_sb_list_cpu`, and `struct super_block` loses `s_files` (f074c267 "get rid of s_files and files_lock").

The 59 changed symbols: `__alloc_pages_nodemask`, `__class_create`, `__free_pages`, `__get_page_tail`, `__mutex_init`, `__pm_runtime_disable`, `__pm_runtime_idle`, `__pm_runtime_resume`, `__register_chrdev`, `class_destroy`, `create_proc_entry`, `device_create`, `device_destroy`, `fget`, `find_vma`, `find_vpid`, `fput`, `get_task_mm`, `get_user_pages`, `ion_alloc`, `ion_client_create`, `ion_client_destroy`, `ion_free`, `ion_map_dma`, `kmalloc_caches`, `kmap`, `kmem_cache_alloc`, `kmem_cache_alloc_trace`, `kmem_cache_create`, `kmem_cache_destroy`, `kmem_cache_free`, `kunmap`, `mem_map`, `mmput`, `module_layout`, `mutex_lock`, `mutex_lock_interruptible`, `mutex_trylock`, `mutex_unlock`, `omap_tiler_pages`, `pid_task`, `pm_runtime_enable`, `proc_mkdir`, `put_page`, `remove_proc_entry`, `seq_lseek`, `seq_open`, `seq_read`, `seq_release`, `sysfs_create_files`, `sysfs_create_group`, `sysfs_remove_files`, `sysfs_remove_group`, `thermal_cooling_dev_register`, `thermal_cooling_dev_unregister`, `vm_insert_mixed`, `vm_insert_page`, `vmalloc_to_page`, `vmap`.

What this means on a device: the stock XE24 module (`/system/lib/modules/pvrsrvkm_sgx540_120.ko`) **will not load** into `tuned-stable` (nor, already, into `tuned`) (`disagrees about version of symbol`), and neither will any other module built for the stock kernel. The boot image must carry the module built with this kernel (see [`hardware-checks.md`](hardware-checks.md)). This is a consequence of the merge, not an ABI break that needs a decision: the module is rebuilt from source with each kernel.

## Hashes

From CI run 39671222156:

| Variant | `zImage` SHA-256 | size | `pvrsrvkm_sgx540_120.ko` SHA-256 | size |
|---|---|---|---|---|
| `stock` (unchanged) | `5b744fef8f8688562e19b8311225f324037aad49901ed78ee6854529de15caa1` | 5,075,816 | `1ec003f32c94512564404bd80b9802f8715d1995df017c5bfae9b99c0cc991c8` | 426,100 |
| `tuned` (unchanged) | `a4f3215246c4fa96f3bec15fadadf3cd70d9ed0ed72d99c400d80118618c1041` | 4,840,000 | `69afa570c35808286acdb3d13e034c665eb3c7ea4105016914ff86bc33d4bb9c` | 402,532 |
| `tuned-stable` | `b66e90d4f03859e43d531c323ba3d76b401290aec075362ddc2655ce70bbe938` | 4,844,888 | `b32408caef5eee58bee4c04db009a4f3e7eb6bbdae196f807fdcd53affcf506b` | 402,644 |

`stock` and `tuned` are byte-identical to main (run 39657896376). Repro run 39671227457 reports `identical` for `Image`, `vmlinux`, `zImage` and the module in all three variants. `tuned-stable`'s `zImage` is 4,888 bytes larger than `tuned`'s.
