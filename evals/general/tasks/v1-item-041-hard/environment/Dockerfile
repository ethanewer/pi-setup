FROM bench-base:ubuntu-24.04

# MIPS cross toolchain (big- and little-endian o32), a QEMU-user MIPS VM, and make.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-mips-linux-gnu gcc-mipsel-linux-gnu \
        libc6-dev-mips-cross libc6-dev-mipsel-cross \
        qemu-user make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/