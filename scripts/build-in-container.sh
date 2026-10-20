#!/bin/sh
# Build the kernel inside the pinned container with docker or podman.
set -eu
cd "$(dirname "$0")/.."
engine=$(command -v docker || command -v podman || true)
[ -n "$engine" ] || { echo "error: docker or podman required" >&2; exit 1; }
"$engine" build --platform linux/amd64 -t glass-kernel-build .
"$engine" run --rm --platform linux/amd64 -v "$PWD:/work" glass-kernel-build sh scripts/build.sh
