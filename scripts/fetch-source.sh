#!/bin/sh
# Fetch Google's Glass kernel source (GPL-2.0) at the pinned commit into src/.
set -eu

cd "$(dirname "$0")/.."
. scripts/source.env

if [ ! -d src/.git ]; then
    git init -q src
    git -C src remote add origin "$REPO"
fi
if [ "$(git -C src rev-parse -q --verify HEAD 2>/dev/null || true)" != "$COMMIT" ]; then
    git -C src fetch -q --depth 1 origin "refs/heads/$BRANCH"
    actual=$(git -C src rev-parse FETCH_HEAD)
    if [ "$actual" != "$COMMIT" ]; then
        echo "error: $BRANCH is at $actual, expected the pinned $COMMIT" >&2
        exit 1
    fi
    git -C src checkout -q --force "$COMMIT"
fi

version=$(awk -F' = ' '/^VERSION/{v=$2} /^PATCHLEVEL/{p=$2} /^SUBLEVEL/{s=$2} END{print v"."p"."s}' src/Makefile)
if [ "$version" != "$EXPECTED_VERSION" ]; then
    echo "error: kernel version $version, expected $EXPECTED_VERSION" >&2
    exit 1
fi
echo "src/ at $BRANCH $COMMIT (Linux $version)"
