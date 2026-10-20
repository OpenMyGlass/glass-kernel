#!/bin/sh
# Fetch and build the kernel inside the pinned container with docker or podman.
# The kernel tree lives in a container volume: Linux 3.4 has paths that differ
# only by case, which a default (case-insensitive) macOS volume corrupts.
set -eu
cd "$(dirname "$0")/.."
engine=$(command -v docker || command -v podman || true)
[ -n "$engine" ] || { echo "error: docker or podman required" >&2; exit 1; }
"$engine" build --platform linux/amd64 -t glass-kernel-build .
"$engine" run --rm --platform linux/amd64 \
    -v "$PWD:/work:Z" -v glass-kernel-src:/work/src \
    -e VARIANT="${VARIANT:-stock}" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    glass-kernel-build sh -c 'scripts/fetch-source.sh && scripts/build.sh && chown -R "$HOST_UID:$HOST_GID" out'
