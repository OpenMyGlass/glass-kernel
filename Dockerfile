# Pinned build environment for the 3.4 kernel, which needs an old GCC.
FROM ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc-arm-linux-gnueabi gcc libc6-dev make bc perl lzop u-boot-tools ca-certificates patch git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
