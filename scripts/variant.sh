#!/bin/sh
# Per-variant settings, sourced by fetch-source.sh and build.sh after source.env.
#   stock         Google's source and notle_defconfig, unchanged.
#   tuned         stock plus configs/tuned.config and patches/tuned/.
#   tuned-stable  tuned, on the linux-3.4.y 3.4.113 merge (STABLE_*) instead of COMMIT.
#   modelb        tuned-stable plus configs/modelb.config: a plain-Linux (Alpine/musl)
#                 base (devtmpfs, VT + framebuffer console) for Model B.
#   modelb-power  modelb plus configs/modelb-power.config: the energy-policy overlay.
# CONFIG_OVERLAYS is the ordered list of config fragments applied over notle_defconfig;
# a later fragment may override an earlier one.
# shellcheck disable=SC2034  # the variables are used by the scripts that source this file
VARIANT=${VARIANT:-stock}
case "$VARIANT" in
    stock|tuned)
        SRC_REPO=$REPO SRC_BRANCH=$BRANCH SRC_COMMIT=$COMMIT SRC_VERSION=$EXPECTED_VERSION ;;
    tuned-stable|modelb|modelb-power)
        SRC_REPO=$STABLE_REPO SRC_BRANCH=$STABLE_BRANCH SRC_COMMIT=$STABLE_COMMIT
        SRC_VERSION=$STABLE_EXPECTED_VERSION ;;
    *) echo "error: VARIANT must be stock, tuned, tuned-stable, modelb or modelb-power" >&2; exit 1 ;;
esac
TUNED=no
CONFIG_OVERLAYS=""
case "$VARIANT" in
    stock) ;;
    tuned|tuned-stable) TUNED=yes; CONFIG_OVERLAYS="configs/tuned.config" ;;
    modelb) TUNED=yes; CONFIG_OVERLAYS="configs/tuned.config configs/modelb.config" ;;
    modelb-power) TUNED=yes
        CONFIG_OVERLAYS="configs/tuned.config configs/modelb.config configs/modelb-power.config" ;;
esac
