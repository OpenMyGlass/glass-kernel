# Model B camera (`modelb-camera` kernel variant)

Model B is the plain-Linux (Alpine/musl) Glass OS. This document is the Phase 3
(camera) investigation: how the Glass camera is actually wired on the OMAP4430
`notle` 3.4 kernel, what the `modelb-camera` config overlay does, and what a real
V4L2 capture pipeline would take. **Read the headline finding first -- it changes
what "enable the camera" means on this hardware.**

## Headline finding: there is no native V4L2 camera driver in this tree

The premise "expose the camera via V4L2 `/dev/video*` / `/dev/media*`" **cannot be
met with the drivers in this 3.4 kernel.** The onboard camera is not a Linux V4L2
device at all. Concretely, in `OpenMyGlass/kernel-omap` at the `modelb` base
(`glass-omap-xrx13b-stable-3.4.113`):

- **No OMAP4 ISS driver.** `drivers/media/` has `omap3isp` (the *OMAP3* ISP -- a
  different SoC block) and `drivers/media/video/omap/` (`omap_vout`, which is
  display *output*, V4L2 overlay, not capture). There is **no `omap4iss`**
  anywhere in the tree. The mainline `omap4iss` V4L2 driver did not exist until
  Linux v3.17 (it was added to `drivers/staging/media/omap4iss`).
- **No sensor subdev, no sensor on any Linux I2C bus.** `arch/arm/mach-omap2/
  board-notle.c` registers I2C devices on buses 1/3/4 (fuel gauge `bq27520`,
  touchpad `rmi_i2c`, panel, IMU `mpu9150`, light sensor `ltr506als`, `glasshub`)
  -- **no camera sensor**. The board file's only camera handles are the sensor
  power rail (`vaux2` / `cam2pwr`, 2.8 V) and the `CAMERA_PWDN` power-down GPIO
  (`notle_camera_sensor_gpio_init()`), whose comment says it powers the sensor
  down "when Ducati:OFF". The sensor's I2C and the ISS are owned by the Ducati,
  not by Linux.
- **The SoC ISS block is in platform data but unclaimed.** The OMAP4 `iss` hwmod,
  `iss_fck` / `iss_ctrlclk` clocks and the `iss_clkdm` clock domain exist in
  `omap_hwmod_44xx_data.c` / `clock44xx_data.c`, and the ISS functional-clock root
  sits *inside the Ducati clock domain* (`CM_CLKSEL_DUCATI_ISS_ROOT`). So the
  plumbing a driver could bind to is present, but nothing binds it.

### How the camera actually works on Glass

Capture runs on the **Ducati IPU** (the OMAP4 dual Cortex-M3 image/video
subsystem). The IPU firmware owns the ISS (ISP + CSI-2 receiver) and the camera
sensor's control bus, and performs ISP processing and encode. Linux is only the
host:

```
  camera sensor --(MIPI CSI-2)--> ISS (ISP) --\
                                               > Ducati IPU (Cortex-M3 x2, runs
  sensor I2C  <------------------------------ /  the ISS + camera firmware)
                                               |
   Linux kernel <--- remoteproc / rpmsg (virtio) --- IPU
        |  omap-remoteproc loads ducati-m3-core0.xem3, keeps it alive (watchdog)
        |  RPMSG_RESMGR: IPU asks Linux to switch cam regulator/clocks/GPIO
        |  RPMSG_OMX  -> /dev/rpmsg-omx0 (ipu_c0), -omx1 (ipu_c1), -omx2 (dsp)
        |  RPC_OMAP   -> /dev/rpmsg-rpc
        v
   userspace camera "HAL": an OMX-IL client (TI domx) that drives an OMX camera
   component on the IPU, exchanging frames through ION / DMM-TILER buffers.
```

So the device nodes that exist for the camera are **`/dev/rpmsg-omx0..2` and
`/dev/rpmsg-rpc`**, not `/dev/video*`. (`notle_defconfig` *does* build the V4L2
core, but the only thing that creates a `/dev/video` is `CONFIG_USB_VIDEO_CLASS`
-- a USB UVC webcam, not the built-in camera.) There is **no `/dev/media*`**
(`CONFIG_MEDIA_CONTROLLER` is off in `notle_defconfig`).

This matches the extracted blob list for XE24 (see the workspace memory note
`glass-device-tree-and-pvr-source`): `ducati-m3-core0.xem3` (IPU, +`-2gb` on
XE-C), `tesla-dsp.xe64T` (DSP), plus the PowerVR and OMX/domx userspace libraries
-- i.e. an Android OMX camera stack, not a V4L2 one.

### Sensor part

The sensor model **cannot be read from this kernel** -- it is not described
anywhere in the Linux source (it lives in the Ducati camera firmware / a vendor
config). Publicly the Explorer Edition camera is a 5 MP still / 720p video module.
Identifying the exact part (believed to be an OmniVision OV-series on a MIPI CSI-2
link) and its I2C address/bus is itself an on-device / firmware-inspection task
and is a prerequisite for the native-V4L2 option below. **Do not assume a part
number.**

## What the `modelb-camera` overlay does

Given the above, the overlay does **not** and **cannot** create a `/dev/video`
for the Glass camera. It does two honest things (see
`configs/modelb-camera.config` for the per-symbol rationale):

**(A) Pins the real (Ducati/OMX) capture path on.** Every symbol below is already
`=y` in `notle_defconfig`, but they are EXPERIMENTAL remoteproc/rpmsg options that
a lean "strip the Android cruft" pass could plausibly drop -- and they are
load-bearing for the camera. Pinning them is a regression guard, exactly the
pattern `configs/modelb-power.config` uses for the already-on power stack.

| Area | Symbols |
| --- | --- |
| V4L2 core (UVC today; prerequisite for a future native driver) | `MEDIA_SUPPORT`, `VIDEO_DEV`, `VIDEO_V4L2_COMMON` |
| Ducati IPU remoteproc | `REMOTEPROC`, `REMOTEPROC_USE_CARVEOUT`, `OMAP_REMOTEPROC`, `OMAP_REMOTEPROC_IPU`, `OMAP_REMOTEPROC_WATCHDOG` |
| IPU MMU | `IOMMU_SUPPORT`, `IOMMU_API`, `OMAP_IOMMU` |
| rpmsg + OMX/RPC channels | `RPMSG`, `RPMSG_RESMGR_FWK`, `RPMSG_RESMGR`, `OMAP_RPMSG_RESMGR`, `RPMSG_OMX`, `RPC_OMAP` |
| Shared-buffer allocators | `ION`, `ION_OMAP`, `DRM_OMAP_DMM_TILER`, `DMA_SHARED_BUFFER`, `CMA` |

**(B) Enables `CONFIG_MEDIA_CONTROLLER`** as forward scaffolding for a future
native `omap4iss` backport. It is **inert on its own** -- nothing binds to it, and
it creates no `/dev/media` -- but it is the framework any native ISS pipeline
needs. It is a `bool` that depends on `EXPERIMENTAL` (on in this tree), so it
lands in the final `.config`.

`VIDEOBUF2_*` is deliberately **not** pinned: those symbols have no Kconfig prompt
(select-only) and `oldconfig` would drop them if nothing selects them, failing the
overlay drop-check. A backported `omap4iss` would `select VIDEOBUF2_DMA_CONTIG`
and pull them in itself.

The IPU carveout `CONFIG_OMAP4_IPU_CMA_SIZE=0x6b00000` (~107 MiB) is left at the
`notle_defconfig` value. The camera/video firmware needs a large IPU carveout;
this value must not be shrunk. It is a hex value (not a boolean) so it is not in
the pinned drop-check list, but it is a hard dependency -- noted here.

**Scope/safety:** the overlay touches no DSS, panel-notle, FPGA, backlight or
power option, so it cannot regress the `modelb` display/firmware bring-up.

### Build it

    VARIANT=modelb-camera scripts/build-in-container.sh

Layers as `tuned -> modelb -> modelb-camera` (not on `modelb-power`).

## Expected device nodes

On a `modelb-camera` boot, once `omap-remoteproc` loads the IPU firmware and the
IPU publishes its rpmsg channels, `devtmpfs` creates:

- `/dev/rpmsg-omx0` (IPU core 0), `/dev/rpmsg-omx1` (IPU core 1), `/dev/rpmsg-omx2`
  (DSP) -- the OMX-IL control channels.
- `/dev/rpmsg-rpc` -- the OMAP RPC channel.
- plus the ION heap device and the OMAP DRM/DMM node used for buffers.

There is **no `/dev/video*` and no `/dev/media*`** for the onboard camera on this
variant. (A `/dev/video0` appears only if a USB UVC webcam is plugged in.)

## The two realistic paths to a working Model B camera

### Option 1 -- reuse the Ducati/OMX path from plain Linux (matches the hardware)

Keep remoteproc + rpmsg + OMX (this overlay already guarantees they are built) and
write a **musl/Alpine userspace camera service** that:

1. waits for `omap-remoteproc` to boot the IPU and for `/dev/rpmsg-omx*` to appear;
2. speaks the OMX-IL protocol over `/dev/rpmsg-omx0` (and `RPC_OMAP` /
   `/dev/rpmsg-rpc`) to instantiate and drive the OMX camera component;
3. allocates frame buffers through ION / DMM-TILER and maps them for preview and
   encode.

What this needs, and the risks:

- **The proprietary IPU firmware `ducati-m3-core0.xem3`** (a Google/TI blob, not in
  any OpenMyGlass repo; extracted from XE24, never committed -- clean-room rule).
  It must be loadable by `omap-remoteproc` on this exact kernel.
- **A port of the TI `domx` / OMX-IL userspace** to musl. The stock stack is
  Android/bionic and uses the Android allocators; it is a substantial port
  (libhybris may help reuse the bionic libs, as planned for the GPU).
- The OMX message formats are not a public ABI -- a **clean-room RE spec** of the
  `/dev/rpmsg-omx` traffic (a separate RE agent, per the project rules) would be
  required to write an open client.
- **Verdict:** this is the path the hardware actually uses and the only one that
  reaches the real ISP today, but it is a large userspace effort, not a kernel
  task, and it never yields a `/dev/video` -- clients must speak OMX.

### Option 2 -- backport the mainline `omap4iss` V4L2 driver (true `/dev/video`)

Drive the OMAP4 ISS directly from Linux, bypassing the Ducati, by backporting the
mainline `drivers/staging/media/omap4iss` driver (added in **Linux v3.17**) plus a
**sensor subdev driver** for the Glass sensor.

A working native pipeline would expose a media graph like:

```
  "OMAP4 ISS CSI2a" :0 -> "OMAP4 ISS CSI2a output" :1 -> /dev/videoN
         ^ pad 0
  <sensor-subdev> :0 ------/
```

and be configured with `media-ctl` + `v4l2-ctl`, e.g.:

```
  media-ctl -r
  media-ctl -l '"<sensor>":0 -> "OMAP4 ISS CSI2a":0 [1]'
  media-ctl -l '"OMAP4 ISS CSI2a":1 -> "OMAP4 ISS CSI2a output":0 [1]'
  media-ctl -V '"<sensor>":0 [fmt:SGRBG10/2592x1944]'   # sensor Bayer out
  media-ctl -V '"OMAP4 ISS CSI2a":1 [fmt:SGRBG10/2592x1944]'
  v4l2-ctl -d /dev/videoN --set-fmt-video=width=2592,height=1944,pixelformat=... \
           --stream-mmap   # capture
```

(resolutions/formats illustrative -- the real ones depend on the sensor, which is
unknown; `omap4iss` CSI-2 output is typically raw Bayer, so demosaic/scaling would
be in userspace or a later ISS stage.)

What this needs, and the risks:

- **Backport effort:** `omap4iss` targets a device-tree OMAP4 and newer V4L2/vb2
  and `media-controller` APIs than 3.4 has; backporting it to this board-file,
  non-DT 3.4 tree is non-trivial (it would need `omap_device` glue to the `iss`
  hwmod, and the vb2/MC APIs checked against 3.4).
- **A sensor subdev driver** for the (unidentified) Glass sensor, with the correct
  I2C bus/address and CSI-2 lane config -- none of which is in-tree.
- **Mutual exclusion with the Ducati:** Linux and the IPU cannot both own the ISS
  and the sensor I2C. Going native means *not* running the camera firmware on the
  IPU (or carefully arbitrating), which interacts with how the IPU is used for
  other codecs.
- **Maturity:** mainline `omap4iss` is staging and was validated on a small set of
  boards/sensors; it is not a drop-in.
- **Verdict:** this is the only path that yields a real `/dev/video` + `media-ctl`
  pipeline, but on 3.4 it is a genuine driver bring-up (backport + new sensor
  driver + de-conflict the IPU), not a config change, and it hinges on identifying
  the sensor.

### Recommendation

The native V4L2 camera belongs in **`OpenMyGlass/glass-mainline`**, not this 3.4
tree. On a mainline (or at least v3.17+) kernel, `omap4iss` is an in-tree driver,
the ISS + CSI-2 + sensor can be described in the device tree, and `media-ctl` works
without a backport. For the 3.4 Model B shipping kernel, the pragmatic camera is
**Option 1** (reuse the Ducati/OMX path via a userspace service), accepting that it
is OMX-based and needs the proprietary IPU firmware + a domx port. Either way, the
kernel side is already in place and guarded by this overlay; the remaining work is
userspace (Option 1) or a mainline-kernel effort (Option 2). **3.4 cannot cleanly
provide native V4L2 capture for this sensor without the Option 2 backport.**

## JPEG / video encode options

- **Hardware (IVA-HD / DSP via OMX):** the stock stack encodes JPEG and H.264 on
  the IVA-HD / DSP (`tesla-dsp.xe64T`) through OMX components on the IPU/DSP. This
  is the efficient path but is only reachable through the OMX stack (Option 1) and
  the proprietary firmware.
- **CPU (libjpeg-turbo / a Rust encoder):** on the native-V4L2 path (Option 2),
  frames arrive as raw Bayer/YUV and JPEG must be done on the Cortex-A9 with
  `libjpeg-turbo` (NEON) or a Rust encoder. Fine for stills; marginal for
  sustained 720p video on this CPU.
- **SGX540 is not a JPEG/video encoder** -- it is a 3D GPU. It can do color-space
  conversion / scaling via shaders but is not the right tool for compressed
  capture; do not plan on it for encode.

## What a future camera service (glassd / a camera daemon) must do

Independently of the chosen path:

- Switch the sensor power on: the `vaux2` / `cam2pwr` regulator and release the
  `CAMERA_PWDN` GPIO (on the Ducati path, `RPMSG_RESMGR` lets the IPU request these
  from Linux; on the native path the service/driver does it directly).
- Manage buffers through ION / DMM-TILER (OMX path) or vb2 MMAP/DMABUF (V4L2 path).
- Provide preview (composite onto the panel via the DSS/`omapfb` the display stack
  already owns) and capture-to-file, with JPEG encode per above.
- Honor the energy policy (see `docs/model-b-energy.md`): power the sensor, ISS and
  IPU down when idle; the camera holds the SoC out of deep idle while active, so
  the service must release it promptly.
- Tie into the camera **button**, which glassd already handles (capability
  `button-camera`); only the capture behind it is missing.
- For the Wi-Fi-QR bootstrap (strategy note), a single still + a Rust QR decoder
  (`rqrr`/`quircs`) is enough -- that use case does not need streaming video and is
  the lightest first consumer of whichever path lands.

## Risks and what needs on-device validation

1. **No `/dev/video` for the onboard camera on this kernel** -- the central fact.
   Anything expecting V4L2 capture from the Glass camera on 3.4 is blocked on
   Option 1 or Option 2 above.
2. **Sensor part is unknown** from the kernel; identifying it (and its I2C
   bus/address + CSI-2 lanes) is a prerequisite for Option 2 and needs on-device /
   firmware inspection.
3. **Proprietary IPU firmware** (`ducati-m3-core0.xem3`) is required for Option 1
   and is not in any OpenMyGlass repo (clean-room rule); its loadability on the
   `modelb-camera` kernel is unverified.
4. **OMX message ABI** is undocumented; an open client needs a clean-room RE spec.
5. **IPU-vs-Linux ownership of the ISS** must be resolved before Option 2.
6. This overlay is **build-verified only.** On device, confirm: the IPU still boots
   and `/dev/rpmsg-omx*` + `/dev/rpmsg-rpc` appear on a `modelb-camera` boot
   (`fastboot boot`, RAM only), and that enabling `MEDIA_CONTROLLER` causes no
   regression (it should be inert). No camera capture has been attempted.
