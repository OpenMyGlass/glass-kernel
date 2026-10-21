#!/bin/sh
# Per-variant settings, sourced by fetch-source.sh and build.sh after source.env.
#   stock         Google's source and notle_defconfig, unchanged.
#   tuned         stock plus configs/tuned.config and patches/tuned/.
#   tuned-stable  tuned, on the linux-3.4.y 3.4.113 merge (STABLE_*) instead of COMMIT.
# shellcheck disable=SC2034  # the variables are used by the scripts that source this file
VARIANT=${VARIANT:-stock}
case "$VARIANT" in
    stock|tuned)
        SRC_REPO=$REPO SRC_BRANCH=$BRANCH SRC_COMMIT=$COMMIT SRC_VERSION=$EXPECTED_VERSION ;;
    tuned-stable)
        SRC_REPO=$STABLE_REPO SRC_BRANCH=$STABLE_BRANCH SRC_COMMIT=$STABLE_COMMIT
        SRC_VERSION=$STABLE_EXPECTED_VERSION ;;
    *) echo "error: VARIANT must be stock, tuned or tuned-stable" >&2; exit 1 ;;
esac
TUNED=no
if [ "$VARIANT" != stock ]; then TUNED=yes; fi
