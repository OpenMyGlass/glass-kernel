#!/bin/sh
# Build zImage from src/ (run inside the container from the Dockerfile).
set -eu
cd "$(dirname "$0")/.."

OUT=$PWD/out
BUILD=$PWD/out/build
mkdir -p "$BUILD"

# Apply our patches to a pristine tree.
git -C src checkout -q --force HEAD
git -C src clean -qfdx
for p in patches/*.patch; do
    [ -e "$p" ] || continue
    echo "applying $p"
    patch -d src -p1 --forward --quiet < "$p"
done

export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- KBUILD_BUILD_USER=openmyglass KBUILD_BUILD_HOST=build KBUILD_BUILD_TIMESTAMP="$(git -C src log -1 --format=%cD)"
make -C src O="$BUILD" notle_defconfig
make -C src O="$BUILD" -j"$(nproc)" zImage

cp "$BUILD/arch/arm/boot/zImage" "$OUT/zImage"
cp "$BUILD/.config" "$OUT/config"
(cd "$OUT" && sha256sum zImage config > SHA256SUMS && cat SHA256SUMS)
