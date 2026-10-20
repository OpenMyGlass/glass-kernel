# glass-kernel

Kernel builds for Google Glass Explorer Edition on its final firmware, XE24 (TI OMAP4430, `notle`). Part of [OpenMyGlass](https://github.com/OpenMyGlass/OpenMyGlass).

## Status

Phase 1: a reproducible build of Google's published kernel source, with no changes yet. Nothing here has been run on hardware yet.

## Source

Google publishes the Glass kernel in [`kernel/omap`](https://android.googlesource.com/kernel/omap) as `glass-omap-*` branches. The newest one, `glass-omap-xrx13b`, is Linux 3.4.94, which matches the version reported for the XE24 factory kernel. It is still unconfirmed which branch XE24 was built from; the check is described in [`docs/hardware-checks.md`](docs/hardware-checks.md).

The kernel tree is not vendored. `scripts/fetch-source.sh` makes a shallow clone of the pinned branch into `src/`.

## Building

The 3.4 kernel needs an old GCC, so builds run in a pinned container (`Dockerfile`: Ubuntu 14.04, `gcc-arm-linux-gnueabi` 4.8, which builds the tree without patches):

```sh
scripts/fetch-source.sh
scripts/build-in-container.sh    # docker or podman
```

The output is `out/zImage` plus `out/config` and `out/SHA256SUMS`. GitHub Actions runs the same build on every push.

## Safety

This repository builds a kernel and does not touch a device. Booting it on Glass comes in a later phase, and only with `fastboot boot`, which runs from RAM and writes nothing. Never flash the `bootloader`, `xloader` or `fpga` partitions: no public way to recover from that is known.

## License

The Linux kernel and every patch in this repository are **GPL-2.0-only** (see [`LICENSE`](LICENSE)). OpenMyGlass's other repositories are GPL-3.0, but kernel code cannot be relicensed.
