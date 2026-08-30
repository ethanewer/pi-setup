# raven-jetty: C reuse + toolchain bench.
#
# Base: python-3.12 (Debian tri) + the C toolchain the bench exercises
# (gcc, clang, make, and binutils/file for the verifier's static-link checks).
# The heavy work (reading the recovered-behavior spec, compiling the clone,
# building modes, fixing+recompiling toycc) happens at agent runtime, so the
# image itself stays lean and builds fast.
FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gcc clang make binutils file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fixtures shipped in the image (none of the deliverables are pre-solved here):
#   /app/behavior-spec.txt  - the recovered-behavior contract for the clone
#   /app/engine/include/...  - the engine's public header tree
#   /app/toycc.c             - the as-shipped (buggy) toy compiler source
COPY files/ /app/