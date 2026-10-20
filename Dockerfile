# Pinned build environment for the 3.4 kernel, which needs an old GCC.
FROM ubuntu:14.04@sha256:64483f3496c1373bfd55348e88694d1c4d0c9b660dee6bfef5e12f43b9933b30
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc-arm-linux-gnueabi gcc libc6-dev make bc perl lzop u-boot-tools ca-certificates patch git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
