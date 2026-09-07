FROM bench-base:ubuntu-24.04

# [environment] declares cpus = 2, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    OPENBLAS_NUM_THREADS=2 \
    NUMEXPR_NUM_THREADS=2

WORKDIR /app

# Native build toolchain for the cedar-canyon math stack (offline-friendly).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc g++ clang libomp-dev cmake make python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Sample workbench fixture (same schema as the hidden cases) so the agent can
# develop and self-test the stack locally.
COPY files/ /app/

WORKDIR /app