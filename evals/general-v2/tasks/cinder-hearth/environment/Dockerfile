# cinder-hearth — emulated-guest runtime for injected-init serial login.
#
# Boots a tiny busybox Linux guest under QEMU software emulation (TCG, no KVM)
# with a prebuilt kernel and a deliberately TRIVIAL base initramfs: the base
# init does NOT mount the pseudo-filesystems, does NOT set up /etc/passwd, and
# does NOT start any getty/login on the serial console. Injecting a real init
# that does all of that is the agent's task.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 busybox-static cpio gzip coreutils python3 \
      linux-image-generic >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "cinder: apt install complete"

WORKDIR /app

# Assemble the prebuilt kernel + trivial base initramfs into /app.
COPY files/build_guest.sh /tmp/build_guest.sh
RUN bash /tmp/build_guest.sh && rm -f /tmp/build_guest.sh
