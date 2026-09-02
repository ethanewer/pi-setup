FROM bench-base:node-22

# MIPS cross toolchain (big- and little-endian o32), a QEMU-user MIPS VM, and make.
# bench-base:node-22 already installs the CA chain (apt works) and ships Node.js,
# which the supplied VM runner (tools/run.js) is written in.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-mips-linux-gnu gcc-mipsel-linux-gnu \
        libc6-dev-mips-cross libc6-dev-mipsel-cross \
        qemu-user make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/