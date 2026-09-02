# iris-ledge — compile & render inside a tiny QEMU guest, kept as a background service
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# qemu (software TCG only, no KVM), a full Linux kernel + its modules for the guest,
# busybox for the tiny guest rootfs, build utilities to assemble the initramfs,
# and a C toolchain that the guest uses (via the shared rootfs) for in-guest
# static compilation — see build_guest.sh and the oracle.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-utils busybox-static cpio zstd gzip \
      linux-image-generic gcc libc6-dev binutils make coreutils >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "iris: apt install complete"

WORKDIR /app

# Assemble the tiny guest (vmlinuz + custom busybox initramfs) into /app.
COPY files/build_guest.sh /tmp/build_guest.sh
RUN bash /tmp/build_guest.sh && rm -f /tmp/build_guest.sh

# The verifier and oracle mount these read-only; they must never be baked in.
RUN mkdir -p /opt/iris/work
