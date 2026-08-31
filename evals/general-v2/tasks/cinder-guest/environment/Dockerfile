# cinder-guest — boot & drive a tiny QEMU guest over a monitor console and a
# serial TCP redirect (software TCG only, no KVM).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# qemu (software TCG), a Linux kernel for the guest, busybox for the tiny guest
# rootfs, and cpio/gzip to assemble the initramfs — see build_guest.sh.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 busybox-static cpio gzip \
      linux-image-generic coreutils procps >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "cinder: apt install complete"

WORKDIR /app

# Assemble the tiny guest (vmlinuz + custom busybox initramfs) into /app.
COPY files/build_guest.sh /tmp/build_guest.sh
RUN bash /tmp/build_guest.sh && rm -f /tmp/build_guest.sh