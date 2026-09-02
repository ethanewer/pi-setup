FROM bench-base:ubuntu-24.04

WORKDIR /app

# Toolchain needed to build + boot a tiny guest initramfs under QEMU (TCG emulation,
# no KVM, no hardware accel). `linux-image-generic` provides /boot/vmlinuz for the
# guest kernel; busybox-host provides the static binary copied into the initramfs
# and doubles as the tiny HTTP host server for the monitoring web port.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        qemu-system-x86 \
        busybox-static \
        cpio \
        file \
        iproute2 \
        linux-image-generic \
 && apt-get clean

# Fixtures: the initramfs descriptor manifest the agent must honour.
COPY files/ /app/files/