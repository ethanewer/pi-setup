# slate-hollow — rescue appliance runtime: injected init, pseudo-fs mounts,
# passwordless getty on the serial console, and a scripted serial login.
#
# Boots a tiny busybox appliance under QEMU software emulation (TCG, no KVM)
# with a prebuilt kernel + a deliberately TRIVIAL base initramfs. The agent
# must author the real init (mount proc/sys/dev, create a passwordless account,
# spawn getty on ttyS0), repack the appliance initramfs, and drive the serial
# console. See build_appliance.sh.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 cpio gzip zstd coreutils \
      curl ca-certificates dpkg python3 make binutils >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "slate: apt install complete"

WORKDIR /app

# Assemble the prebuilt kernel + trivial base initramfs into /app. The agent
# must NOT modify these, but must inject a custom init and repack.
COPY files/build_appliance.sh /tmp/build_appliance.sh
RUN bash /tmp/build_appliance.sh && rm -f /tmp/build_appliance.sh
