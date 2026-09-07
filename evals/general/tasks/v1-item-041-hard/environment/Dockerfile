FROM bench-base:node-22

# MIPS cross toolchain (big- and little-endian o32), a QEMU-user MIPS VM, and make.
# bench-base:node-22 already installs the CA chain (apt works) and ships Node.js,
# which the supplied VM runner (tools/run.js) is written in.
#
# This must be node-22, not ubuntu-24.04. The verifier rebuilds from the agent's
# sources and then runs `node tools/run.js out.elf`, comparing the frame it emits
# against a fixed digest. On bench-base:ubuntu-24.04 node exists only under nvm at
# /root/.nvm/versions/node/*/bin and is not on PATH for a non-interactive shell,
# so that call exits 127, frame_ok stays 0, and full credit is unreachable no
# matter what the agent does. The sibling task v1-item-041-main has always used
# node-22 for exactly this reason.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-mips-linux-gnu gcc-mipsel-linux-gnu \
        libc6-dev-mips-cross libc6-dev-mipsel-cross \
        qemu-user make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/