# brisk-jetty — emulated "Nysa relay appliance" with serial-console first-run
# enrollment, host->guest port forwarding and a repaired live network fetch.
#
# The appliance OS is a distro-less busybox+dropbear guest provisioned by the
# supplied fixture /opt/gk/mkguest.sh (baked into this image). The guest is
# deliberately UNENROLLED at boot: sshd and the relay panel stay disabled until
# someone logs into the serial console as root and runs the first-run steps.
# The agent must drive that console non-interactively, forward two host ports
# into the guest (ssh + a tiny relay panel), prove ssh reachability, repair the
# broken host name resolution for the relay hostname, and capture a genuine live
# fetch over the repaired path.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# qemu (software TCG only, no /dev/kvm), a distro kernel + static busybox for the
# tiny guest rootfs, dropbear (the real ssh server embedded in the guest), host
# ssh client + sshpass for password ssh, and build/emulation utilities.
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      qemu-system-x86 \
      qemu-utils \
      busybox-static \
      dropbear \
      openssl \
      openssh-client \
      sshpass \
      cpio \
      gzip \
      zstd \
      file \
      python3 \
      iproute2 \
      procps \
      linux-image-generic >/tmp/apt.log 2>&1 ; echo "apt_exit=$?" ; tail -2 /tmp/apt.log

# Bake a bootable distro kernel + static busybox + dropbear binaries (the guest
# userland sources) and the decompressed virtio driver modules the guest needs to
# bring eth0 up for the host->guest forwards.
RUN mkdir -p /opt/gk/modules && \
    cp -L /boot/vmlinuz-* /opt/gk/vmlinuz && \
    cp -L /bin/busybox /opt/gk/busybox && \
    cp -L "$(command -v dropbear)" /opt/gk/dropbear && \
    cp -L "$(command -v dropbearkey)" /opt/gk/dropbearkey && \
    moddir=$(ls -d /usr/lib/modules/*/ 2>/dev/null | head -1) && \
    for m in virtio virtio_ring virtio_pci virtio_net; do \
      f=$(find "$moddir" -name "${m}.ko*" 2>/dev/null | head -1); \
      if [ -n "$f" ]; then zstd -d -q -c "$f" > /opt/gk/modules/${m}.ko 2>/dev/null || cp "$f" /opt/gk/modules/${m}.ko; fi; \
    done && \
    echo "[gk]" && ls -la /opt/gk && ls -la /opt/gk/modules && \
    echo "[gk] ok"

# The supplied fixture: provisions the (still unenrolled) guest OS initramfs.
COPY files/mkguest.sh /opt/gk/mkguest.sh
ENV NYSA_ROOT_PASSWORD=kestrel-mistral-1987
RUN chmod +x /opt/gk/mkguest.sh && bash /opt/gk/mkguest.sh && \
    ls -la /opt/gk/guest-initrd.cpio.gz && echo "[gk] guest os built"

# The host's network path to the relay appliance is genuinely broken: the
# hostname "nysa.test" has NO /etc/hosts entry, so a live fetch of
# http://nysa.test:18080/live fails to resolve until the agent repairs host
# name resolution (append "127.0.0.1 nysa.test") and reaches the guest relay
# panel through the qemu user-net forward on loopback.

WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive
