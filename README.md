# glass-kernel

Kernel builds for Google Glass Explorer Edition on its final firmware, XE24 (TI OMAP4430, `notle`). Part of [OpenMyGlass](https://github.com/OpenMyGlass/OpenMyGlass).

## Status

Phase 3: GPU module built from source (DDK 1.9@2166536), importing the same kernel symbols with the same CRCs as the stock module (not yet run on hardware). See [`docs/gpu-module.md`](docs/gpu-module.md).

Phase 2: tuning prepared, not yet measured on hardware. There are runtime profiles (`tuning/omg-tune.sh`: `stock`, `balanced`, `cool`) and a `tuned` build variant (deadline I/O scheduler, no debug-only statistics). See [`docs/tuning.md`](docs/tuning.md).

Phase 1: a reproducible build of Google's published kernel source, with no changes yet. Nothing here has been run on hardware yet.

## Source

Google publishes the Glass kernel in [`kernel/omap`](https://android.googlesource.com/kernel/omap) as `glass-omap-*` branches. The newest one, `glass-omap-xrx13b`, is Linux 3.4.94, which matches the version reported for the XE24 factory kernel. It is still unconfirmed which branch XE24 was built from; the check is described in [`docs/hardware-checks.md`](docs/hardware-checks.md).

The kernel tree is not vendored. `scripts/fetch-source.sh` makes a shallow clone of the pinned commit (`scripts/source.env`) into `src/`. It runs in the container. `src/` is managed by the scripts: local edits there are discarded on each build.

## Building

The 3.4 kernel needs an old GCC, so builds run in a pinned container (`Dockerfile`: Ubuntu 14.04, `gcc-arm-linux-gnueabi` 4.7 (Linaro 4.7.3), which builds the tree without patches):

```sh
scripts/build-in-container.sh    # docker or podman: fetches src/ and builds
```

The kernel tree is kept in a container volume (`glass-kernel-src`) because Linux 3.4 has paths that differ only by case, which a default macOS volume cannot hold.

`pvr/` (the GPU driver source) is fetched on the host by `scripts/fetch-pvr.sh`, which needs git 2.25 or newer.

The build also produces the GPU module, `out/pvrsrvkm_sgx540_120.ko`. The output is `out/zImage` plus `out/config` and `out/SHA256SUMS`. Builds are bit-for-bit reproducible: `scripts/check-reproducible.sh` (the `repro` workflow) builds twice and compares `Image`, `vmlinux`, `zImage` and `pvrsrvkm_sgx540_120.ko`. `__DATE__`/`__TIME__`, which the `bcmdhd` Wi-Fi driver embeds, are pinned to the source commit date. GitHub Actions runs the same build on every push.

## Safety

This repository builds a kernel and does not touch a device. Booting it on Glass is done only with `fastboot boot`, which runs from RAM and writes nothing. Never flash the `bootloader`, `xloader` or `fpga` partitions: no public way to recover from that is known.

## License

The Linux kernel and every patch in this repository are **GPL-2.0-only** (see [`LICENSE`](LICENSE)). OpenMyGlass's other repositories are GPL-3.0, but kernel code cannot be relicensed.
