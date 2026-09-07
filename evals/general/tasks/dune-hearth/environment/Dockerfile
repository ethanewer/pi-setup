FROM bench-base:ubuntu-24.04

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive
# toolchain for the serial/OpenMP/MPI builds plus the archiving steps
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc g++ make \
      cmake \
      libopenmpi-dev openmpi-bin \
      zstd \
      python3 \
      file \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# no fixtures are shipped; the agent authors the project from the spec