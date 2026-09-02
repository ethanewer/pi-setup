FROM bench-base:ubuntu-24.04

# Gale Pier bring-up lab: kernel build toolchain, QEMU, static busybox for the
# guest rootfs, cpio for initramfs packaging, and the Linux source tarball from
# the distro so the kernel is compiled at agent runtime (no vendored tree).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    cpio \
    gpg \
    linux-source \
    qemu-system-x86 \
    busybox-static \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/