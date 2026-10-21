#!/bin/sh
# Fetch the kernel source of $VARIANT (GPL-2.0) at its pinned commit into src/:
# Google's glass-omap-xrx13b for stock and tuned, OpenMyGlass's 3.4.113 merge for tuned-stable.
set -eu

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. scripts/source.env
# shellcheck disable=SC1091
. scripts/variant.sh

if [ ! -d src/.git ]; then
    git init -q src
    git -C src remote add origin "$REPO"
fi
if [ "$(git -C src rev-parse -q --verify HEAD 2>/dev/null || true)" != "$SRC_COMMIT" ]; then
    git -C src fetch -q --depth 1 "$SRC_REPO" "refs/heads/$SRC_BRANCH"
    actual=$(git -C src rev-parse FETCH_HEAD)
    if [ "$actual" != "$SRC_COMMIT" ]; then
        echo "error: $SRC_BRANCH is at $actual, expected the pinned $SRC_COMMIT" >&2
        exit 1
    fi
    git -C src checkout -q --force "$SRC_COMMIT"
fi

version=$(awk -F' = ' '/^VERSION/{v=$2} /^PATCHLEVEL/{p=$2} /^SUBLEVEL/{s=$2} END{print v"."p"."s}' src/Makefile)
if [ "$version" != "$SRC_VERSION" ]; then
    echo "error: kernel version $version, expected $SRC_VERSION" >&2
    exit 1
fi
echo "src/ at $SRC_BRANCH $SRC_COMMIT (Linux $version)"
