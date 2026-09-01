FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
# Cross toolchain (little-endian MIPS) + qemu user-mode to run it, native C and
# Fortran toolchains, make, and CPython (used as the second polyglot toolchain
# and to host the Scheme evaluator). Installs cleanly via the corporate proxy.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        gcc \
        gfortran \
        gcc-mipsel-linux-gnu \
        libc6-dev-mipsel-cross \
        make \
        qemu-user-static \
        python3 \
        >/dev/null

WORKDIR /app

# Provided fixtures: C "game" source and the (unmodified) Fortran library+main
# plus the legacy Makefile that must be retargeted to gfortran.
COPY files/ /app/
