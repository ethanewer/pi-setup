# kite-anchor — FK81 physics-lab toolchain bundle.
#
# Multi-toolchain lab: native C/C++/Fortran, a MIPS cross toolchain whose ELF
# is executed under qemu-user-static, a Python external launcher, and a Scheme
# metacircular evaluator written by the agent.  CPU-only, offline.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# gcc/g++ (native), gfortran, MIPS little-endian cross toolchain + its cross
# libc, qemu user-mode interpreter for running the MIPS ELF, plus build/id
# utilities and python3 for the launcher and evaluator harness.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      gcc g++ gfortran make \
      gcc-mipsel-linux-gnu libc6-dev-mipsel-cross \
      qemu-user-static python3 file >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "kite-anchor: apt install complete"

WORKDIR /app

# Immutable lab inputs (do not modify these when authoring the deliverables):
COPY files/hop.c        /app/sources/hop.c
COPY files/geom.f90     /app/sources/geom.f90
COPY files/drive.f90    /app/sources/drive.f90
COPY files/Makefile.in  /app/sources/Makefile.fk81
COPY files/kite_app.c   /app/sources/kite_app.c
COPY files/launcher.py  /app/launcher.py
# Official release seeds for which /app/key.txt must be produced.
COPY files/key_seeds.txt /app/sources/key_seeds.txt

RUN chmod +x /app/launcher.py && \
    mkdir -p /app/out && \
    echo "kite-anchor: fixtures in place"

CMD ["/bin/bash"]