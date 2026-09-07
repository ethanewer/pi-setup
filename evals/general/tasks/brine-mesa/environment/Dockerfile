FROM bench-base:ubuntu-24.04

# [environment] declares cpus = 4, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=4 \
    MKL_NUM_THREADS=4 \
    OPENBLAS_NUM_THREADS=4 \
    NUMEXPR_NUM_THREADS=4

WORKDIR /app

# Native toolchain with OpenMP runtime for the drift simulator.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc libomp-dev python3 binutils file \
 && rm -rf /var/lib/apt/lists/*

# Shipped visible fixture (hidden fixtures follow the same schema).
COPY files/ /app/
