# basalt-bridge — headless software-emulated guest service on a loop-port forward.
#
# Boots a tiny busybox Linux guest under QEMU software emulation (TCG, no /dev/kvm),
# forwards a host loopback port into the guest's sshd via QEMU user-mode networking,
# keeps the emulator running as a background (daemonized) service after the launching
# session exits, and repairs a broken /usr/bin/curl so a live loopback fetch returns
# the exact original remote content. All runtime is offline.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# qemu (software TCG only), a distro kernel + static busybox for the guest initramfs,
# dropbear (real SSH server embedded in the guest), host usertools, and img/cpio tools.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
        qemu-system-x86 \
        qemu-utils \
        busybox-static \
        dropbear \
        cpio \
        gzip \
        zstd \
        curl \
        python3 \
        iproute2 \
        file \
        linux-image-generic >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "basalt-bridge: apt install complete"

# A bootable distro kernel + static busybox + decompressed virtio driver modules.
# The guest needs virtio_net (and its deps) to bring eth0 up for the host->guest
# port forward; we ship uncompressed .ko for the exact kernel we boot.
RUN mkdir -p /opt/gk && \
    cp -L /boot/vmlinuz-* /opt/gk/vmlinuz && \
    cp -L /bin/busybox /opt/gk/busybox && \
    mkdir -p /opt/gk/modules && \
    moddir=$(ls -d /usr/lib/modules/*/ 2>/dev/null | head -1) && \
    for m in virtio virtio_ring virtio_pci virtio_net; do \
      f=$(find "$moddir" -name "${m}.ko*" 2>/dev/null | head -1); \
      if [ -n "$f" ]; then zstd -q -d -c "$f" > /opt/gk/modules/${m}.ko 2>/dev/null || cp "$f" /opt/gk/modules/${m}.ko; fi; \
    done; \
    echo "guest-kernel:" && ls -la /opt/gk && echo "modules:" && ls -la /opt/gk/modules && \
    echo ok

# (Pre-baked before the curl sabotage: the claude-code agent CLI is installed
# here so the eval harness's agent-installer — which shells out to /usr/bin/curl
# and would hit the stub — is skipped at trial time; it is inert for task
# semantics and for other agents.)
RUN curl -fsSL https://downloads.claude.ai/claude-code-releases/bootstrap.sh | bash -s -- \
 && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
 && claude --version

# Save a pristine curl for restoration, then break /usr/bin/curl into a stub so a
# pristine container is broken until repaired (the agent must restore a genuine ELF).
RUN cp -f "$(command -v curl)" /opt/gk/curl.orig && \
    chmod 0755 /opt/gk/curl.orig && \
    printf '#!/bin/bash\nprintf "BASALT-STUB: curl unavailable\n" >&2\nexit 7\n' > /usr/bin/curl && \
    chmod 0755 /usr/bin/curl

WORKDIR /app

# Host-side loopback "remote telescope" served content (the true remote bytes).
COPY files/origin/ /app/origin/

CMD ["/bin/bash"]