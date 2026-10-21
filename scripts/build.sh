#!/bin/sh
# Build zImage from src/ and pvrsrvkm from pvr/ (run inside the container from the Dockerfile).
# src/ is a managed checkout: local edits there are discarded on every build.
set -eu
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. scripts/source.env

# Never let git fall through to this repository when src/ is not its own checkout.
if [ ! -d src/.git ] || [ "$(git -C src rev-parse HEAD)" != "$COMMIT" ]; then
    echo "error: src/ is not a checkout of $COMMIT; run scripts/fetch-source.sh" >&2
    exit 1
fi
# pvr/ is fetched by a newer git than the container's, which cannot open it: read HEAD directly.
if [ "$(cat pvr/.git/HEAD 2>/dev/null || true)" != "$PVR_COMMIT" ]; then
    echo "error: pvr/ is not a checkout of $PVR_COMMIT; run scripts/fetch-pvr.sh" >&2
    exit 1
fi

VARIANT=${VARIANT:-stock}
case "$VARIANT" in
    stock|tuned) ;;
    *) echo "error: VARIANT must be stock or tuned" >&2; exit 1 ;;
esac

OUT=$PWD/out
BUILD=$PWD/out/build
rm -rf "$BUILD"
mkdir -p "$BUILD"

# Apply our patches to a pristine tree: patches/ for every variant, then patches/<variant>/.
git -C src checkout -q --force "$COMMIT"
git -C src clean -qfdx
patch_dirs=patches
if [ "$VARIANT" = tuned ]; then patch_dirs="patches patches/tuned"; fi
for d in $patch_dirs; do
    for p in "$d"/*.patch; do
        [ -e "$p" ] || continue
        echo "applying $p"
        git -C src apply --check "../$p"
        git -C src apply "../$p"
    done
done

KBUILD_BUILD_TIMESTAMP=$(git -C src log -1 --format=%cD)
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- \
    KBUILD_BUILD_USER=openmyglass KBUILD_BUILD_HOST=build KBUILD_BUILD_VERSION=1 \
    KBUILD_BUILD_TIMESTAMP
# Some drivers (bcmdhd) embed __DATE__/__TIME__; pin them to the source commit date so
# two builds of the same commit are bit-identical. GCC 4.7 predates SOURCE_DATE_EPOCH.
commit_epoch=$(git -C src log -1 --format=%ct)
cat > "$OUT/build-date.h" <<EOH
#define __DATE__ "$(date -u -d "@$commit_epoch" '+%b %e %Y')"
#define __TIME__ "$(date -u -d "@$commit_epoch" '+%H:%M:%S')"
EOH
export KCFLAGS="-Wno-builtin-macro-redefined -include $OUT/build-date.h"
make -C src O="$BUILD" notle_defconfig
# scripts/config in 3.4 takes option names without the CONFIG_ prefix.
opt_name() { echo "${1#CONFIG_}"; }
if [ "$VARIANT" = tuned ]; then
    # Apply the fragment, let Kconfig resolve dependencies, then check nothing was dropped.
    grep -v '^#\( \|$\)' configs/tuned.config | grep . > "$BUILD/fragment" || true
    while read -r line; do
        case "$line" in
            *=y) src/scripts/config --file "$BUILD/.config" --enable "$(opt_name "${line%%=*}")" ;;
            *=*) src/scripts/config --file "$BUILD/.config" --set-val "$(opt_name "${line%%=*}")" "${line#*=}" ;;
        esac
    done < "$BUILD/fragment"
    sed -n 's/^# \(CONFIG_[A-Z0-9_]*\) is not set$/\1/p' configs/tuned.config | while read -r opt; do
        src/scripts/config --file "$BUILD/.config" --disable "$(opt_name "$opt")"
    done
    yes "" | make -C src O="$BUILD" oldconfig >/dev/null
    while read -r line; do
        grep -qxF "$line" "$BUILD/.config" || { echo "error: Kconfig dropped '$line'" >&2; exit 1; }
    done < "$BUILD/fragment"
    sed -n 's/^\(# CONFIG_[A-Z0-9_]* is not set\)$/\1/p' configs/tuned.config | while read -r line; do
        opt=${line#\# }; opt=${opt%% *}
        if grep -q "^$opt=" "$BUILD/.config"; then echo "error: Kconfig kept $opt" >&2; exit 1; fi
    done
fi
make -C src O="$BUILD" -j"$(nproc)" zImage

# Build the SGX module against the built tree, from a patched copy of the DDK in out/.
make -C src O="$BUILD" -j"$(nproc)" modules_prepare
PVR_BUILD=$OUT/pvr-build
ko=pvrsrvkm_sgx540_120.ko
rm -rf "${PVR_BUILD:?}" "${OUT:?}/$ko"
cp -R "pvr/$PVR_PATH" "$PVR_BUILD"
for p in pvr-patches/*.patch; do
    [ -e "$p" ] || continue
    echo "applying $p"
    patch -d "$PVR_BUILD" -p1 --dry-run -s < "$p" >/dev/null
    patch -d "$PVR_BUILD" -p1 -s < "$p"
done
make -C "$PVR_BUILD/eurasiacon/build/linux2/omap4430_android" -j"$(nproc)" \
    CROSS_COMPILE=arm-linux-gnueabi- KERNEL_CROSS_COMPILE=arm-linux-gnueabi- \
    KERNELDIR="$BUILD" BUILD=release TARGET_PRODUCT=blaze_tablet TARGET_SGX=540 \
    PLATFORM_VERSION=4.0 OUT="$PVR_BUILD/binary" kbuild
cp "$PVR_BUILD/binary/target/$ko" "$OUT/$ko" 2>/dev/null || true
test -s "$OUT/$ko" || { echo "error: $ko was not built" >&2; exit 1; }
arm-linux-gnueabi-strip --strip-unneeded "$OUT/$ko"

cp "$BUILD/arch/arm/boot/zImage" "$OUT/zImage"
cp "$BUILD/.config" "$OUT/config"
(cd "$OUT" && sha256sum zImage "$ko" config > SHA256SUMS && cat SHA256SUMS && wc -c zImage "$ko")
