# larch-hearth — emulated-guest runtime: cdrom boot/mount, in-guest static
# asm compile, host-fs syscall/file-io via 9p, and injected serial login.
#
# Boots a tiny busybox Linux guest under QEMU software emulation (TCG, no KVM)
# with a pre-built kernel + a deliberately TRIVIAL base initramfs. The agent
# must inject a real init (mount cdrom, mount 9p host root, run in-guest work,
# enable serial login), assemble a tool CD as guest.iso, boot, drive the serial
# console, and capture serial.log. See build_guest.sh.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# qemu (software TCG only), a prebuilt Linux kernel + modules, busybox for the
# guest rootfs, img tools to author the guest.iso (xorriso/isoinfo), and a C
# toolchain that the guest reaches via the 9p-shared container root so it can
# compile a static assembly-level program inside the guest.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-utils busybox-static cpio zstd gzip xorriso \
      linux-image-generic gcc libc6-dev binutils make coreutils \
      python3 unzip iproute2 >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "larch: apt install complete"

WORKDIR /app

# Assemble the prebuilt kernel + trivial base initramfs into /app. The agent
# must NOT modify these, but must inject a custom init and author guest.iso.
COPY files/build_guest.sh /tmp/build_guest.sh
RUN bash /tmp/build_guest.sh && rm -f /tmp/build_guest.sh

# Shared host-fs work area: the guest reaches it via the 9p host-root mount and
# its syscall file-writes land here for the host/verifier to read.
RUN mkdir -p /opt/larch/work
