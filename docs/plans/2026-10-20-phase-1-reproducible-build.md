# Phase 1: Reproducible build of the stock XE24 kernel source — Plan

**Goal:** Anyone can build `zImage` from Google's `glass-omap-xrx13b` with `notle_defconfig`, getting the same result locally (docker/podman) and in GitHub Actions. There are no functional kernel changes in this phase.

**Source facts:** see the README. The branch is pinned to a commit hash, not only a branch name.

## Constraints
- GPL-2.0-only. The kernel tree is not committed; it is fetched by a script, shallow and pinned.
- No Google proprietary files: the kernel is GPL. Firmware blobs are never fetched.
- No device access in this phase.

## Tasks
1. `scripts/fetch-source.sh`: shallow clone of the branch, check out the pinned commit, verify `Makefile` VERSION/PATCHLEVEL/SUBLEVEL = 3.4.94. The script is idempotent.
2. `Dockerfile` (ubuntu:14.04 — see the ruling below, gcc-arm-linux-gnueabi, make, bc, perl, lzop, u-boot-tools) and `scripts/build.sh` (`make ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- notle_defconfig zImage`, then copy the artifacts and write SHA256SUMS). `scripts/build-in-container.sh` picks docker or podman.
3. Compiler fixes needed for gcc 5, kept as numbered patches in `patches/` and applied by the build. Each patch has a header explaining why it is needed.
4. `.github/workflows/build.yml`: build in the container and upload the artifacts.
5. `docs/hardware-checks.md`: what to compare on a real XE24 (`/proc/version`, `/proc/config.gz` against `out/config`) before any boot test.

## Rulings
- Ubuntu 16.04 (GCC 5) fails on `linux/compiler-gcc5.h`. The build uses Ubuntu 14.04 (GCC 4.7) so the tree stays unpatched; task 3 is empty for now. Cost if wrong: an EOL base image, to be replaced with a GCC 5+ patchset later.

## Done when
CI is green and produces a `zImage`, and two builds of the same commit report the same `out/config`.
