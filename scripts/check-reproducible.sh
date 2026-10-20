#!/bin/sh
# Build twice from scratch and report where the outputs differ (run in the container).
set -eu
cd "$(dirname "$0")/.."
scripts/build.sh >/dev/null
mkdir -p out/first
cp out/build/arch/arm/boot/Image out/build/vmlinux out/zImage out/first/
cp -r out/build/usr out/first/usr 2>/dev/null || true
scripts/build.sh >/dev/null
for f in Image vmlinux zImage; do
    a=out/first/$f
    b=$( [ "$f" = zImage ] && echo out/zImage || echo out/build/$( [ "$f" = Image ] && echo arch/arm/boot/Image || echo vmlinux ))
    if cmp -s "$a" "$b"; then echo "$f: identical"; else echo "$f: DIFFERS ($(cmp -l "$a" "$b" | wc -l) bytes)"; fi
done
if ! cmp -s out/first/vmlinux out/build/vmlinux; then
    for s in $(arm-linux-gnueabi-objdump -h out/build/vmlinux | awk '$1 ~ /^[0-9]+$/ {print $2}'); do
        arm-linux-gnueabi-objcopy -O binary -j "$s" out/first/vmlinux /tmp/a 2>/dev/null || continue
        arm-linux-gnueabi-objcopy -O binary -j "$s" out/build/vmlinux /tmp/b 2>/dev/null || continue
        cmp -s /tmp/a /tmp/b || echo "section $s differs"
    done
    strings -n 8 out/first/vmlinux > /tmp/sa; strings -n 8 out/build/vmlinux > /tmp/sb
    diff /tmp/sa /tmp/sb | head -40 || true
fi
