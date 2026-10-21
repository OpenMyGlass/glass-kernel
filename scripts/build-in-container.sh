#!/bin/sh
# Fetch and build the kernel and the SGX module inside the pinned container with docker or podman.
# The kernel tree lives in a container volume: Linux 3.4 has paths that differ
# only by case, which a default (case-insensitive) macOS volume corrupts.
set -eu
cd "$(dirname "$0")/.."
engine=$(command -v docker || command -v podman || true)
[ -n "$engine" ] || { echo "error: docker or podman required" >&2; exit 1; }
# fetch-pvr.sh runs on the host and needs git 2.25 or newer (sparse-checkout, partial clone);
# the container's git 1.9 has neither.
scripts/fetch-pvr.sh
"$engine" build --platform linux/amd64 -t glass-kernel-build .
"$engine" run --rm --platform linux/amd64 \
    -v "$PWD:/work:Z" -v glass-kernel-src:/work/src \
    -e VARIANT="${VARIANT:-stock}" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    glass-kernel-build sh -c 'scripts/fetch-source.sh && scripts/build.sh && chown -R "$HOST_UID:$HOST_GID" out'
