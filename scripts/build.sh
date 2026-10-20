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

VARIANT=${VARIANT:-stock}
case "$VARIANT" in
    stock|tuned) ;;
    *) echo "error: VARIANT must be stock or tuned" >&2; exit 1 ;;
esac

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
    grep -v '^#\( \|$\)' configs/tuned.config | grep . > "$BUILD/fragment"
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

cp "$BUILD/arch/arm/boot/zImage" "$OUT/zImage"
cp "$BUILD/.config" "$OUT/config"
(cd "$OUT" && sha256sum zImage config > SHA256SUMS && cat SHA256SUMS)
