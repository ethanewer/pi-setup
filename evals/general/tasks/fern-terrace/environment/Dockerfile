FROM bench-base:ubuntu-24.04

# The host toolchain for this task: full-system QEMU (software emulation, no
# /dev/kvm available), a distro kernel to boot guests, a minimal userland for
# guests (busybox-static + dropbear ssh), disk/partition tooling and a CD image
# generator. Everything is installed here at build time so the agent needs no
# runtime network access.
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      qemu-system-x86 \
      busybox-static \
      dropbear \
      openssl \
      genisoimage \
      e2fsprogs \
      dosfstools \
      fdisk gdisk \
      cpio \
      sshpass \
      openssh-client \
      util-linux \
      iproute2 iputils-ping net-tools procps \
      linux-image-generic >/tmp/apt.log 2>&1 ; echo "apt_exit=$?" ; tail -2 /tmp/apt.log

# Bake a bootable distro kernel for guests into the image.
RUN mkdir -p /opt/gk && \
    cp -L /boot/vmlinuz-* /opt/gk/vmlinuz && \
    cp -L /bin/busybox /opt/gk/busybox && \
    echo "kernel:" && ls -la /opt/gk

WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive
