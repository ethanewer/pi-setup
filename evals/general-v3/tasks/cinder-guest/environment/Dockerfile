# cinder-guest — boot & drive a tiny x86_64 QEMU guest over a monitor console
# and a serial TCP redirect (software TCG only, no KVM).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# qemu (software TCG), cpio/gzip to assemble the initramfs, python3 + coreutils
# for the pinned-deb fetch in build_guest.sh. The guest kernel and busybox come
# from sha256-pinned amd64 .deb archives fetched during build (the host may be
# arm64, whose distro kernel qemu-system-x86_64 cannot boot) — see build_guest.sh.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 cpio gzip python3 coreutils procps >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "cinder: apt install complete"

WORKDIR /app

# Assemble the tiny guest (vmlinuz + custom busybox initramfs) into /app.
COPY files/build_guest.sh /tmp/build_guest.sh
RUN bash /tmp/build_guest.sh && rm -f /tmp/build_guest.sh