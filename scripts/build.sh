#!/bin/sh
# Build zImage from src/ (run inside the container from the Dockerfile).
# src/ is a managed checkout: local edits there are discarded on every build.
set -eu
cd "$(dirname "$0")/.."
. scripts/source.env

# Never let git fall through to this repository when src/ is not its own checkout.
if [ ! -d src/.git ] || [ "$(git -C src rev-parse HEAD)" != "$COMMIT" ]; then
    echo "error: src/ is not a checkout of $COMMIT; run scripts/fetch-source.sh" >&2
    exit 1
fi

OUT=$PWD/out
BUILD=$PWD/out/build
rm -rf "$BUILD"
mkdir -p "$BUILD"

# Apply our patches to a pristine tree.
git -C src checkout -q --force "$COMMIT"
git -C src clean -qfdx
for p in patches/*.patch; do
    [ -e "$p" ] || continue
    echo "applying $p"
    git -C src apply --check "../$p"
    git -C src apply "../$p"
done

export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- \
    KBUILD_BUILD_USER=openmyglass KBUILD_BUILD_HOST=build KBUILD_BUILD_VERSION=1 \
    KBUILD_BUILD_TIMESTAMP="$(git -C src log -1 --format=%cD)"
# Some drivers (bcmdhd) embed __DATE__/__TIME__; pin them to the source commit date so
# two builds of the same commit are bit-identical. GCC 4.7 predates SOURCE_DATE_EPOCH.
commit_epoch=$(git -C src log -1 --format=%ct)
build_date=$(date -u -d "@$commit_epoch" '+%b %e %Y')
build_time=$(date -u -d "@$commit_epoch" '+%H:%M:%S')
export KCFLAGS="-Wno-builtin-macro-redefined -D__DATE__=\"\\\"$build_date\\\"\" -D__TIME__=\"\\\"$build_time\\\"\""
make -C src O="$BUILD" notle_defconfig
make -C src O="$BUILD" -j"$(nproc)" zImage

cp "$BUILD/arch/arm/boot/zImage" "$OUT/zImage"
cp "$BUILD/.config" "$OUT/config"
(cd "$OUT" && sha256sum zImage config > SHA256SUMS && cat SHA256SUMS)
