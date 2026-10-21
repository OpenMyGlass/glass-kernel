#!/bin/sh
# Fetch the SGX DDK kernel sources at the pinned commit into pvr/ (only PVR_PATH).
set -eu

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. scripts/source.env

if [ ! -d pvr/.git ]; then
    git init -q pvr
    git -C pvr remote add origin "$PVR_REPO"
fi
git -C pvr remote set-url origin "$PVR_REPO"
if [ "$(git -C pvr rev-parse -q --verify HEAD 2>/dev/null || true)" != "$PVR_COMMIT" ]; then
    git -C pvr fetch -q --depth 1 --filter=blob:none origin "$PVR_COMMIT"
    git -C pvr sparse-checkout set "$PVR_PATH"
fi
# build.sh copies the DDK from here, so discard any local edits.
git -C pvr checkout -q --force "$PVR_COMMIT"
git -C pvr clean -qfdx

h=pvr/$PVR_PATH/include4/pvrversion.h
if [ ! -f "$h" ]; then
    echo "error: $h not found at $PVR_COMMIT" >&2
    exit 1
fi
branch=$(awk '$2 == "PVRVERSION_BRANCHNAME" {gsub(/"/, "", $3); print $3}' "$h")
build=$(awk '$2 == "PVRVERSION_BUILD" {print $3}' "$h")
if [ "$branch" != "$PVR_EXPECTED_BRANCH" ] || [ "$build" != "$PVR_EXPECTED_BUILD" ]; then
    echo "error: DDK is $branch@$build, expected $PVR_EXPECTED_BRANCH@$PVR_EXPECTED_BUILD" >&2
    exit 1
fi
echo "pvr/ at $PVR_COMMIT (DDK $branch@$build)"
