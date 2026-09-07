# kite-yonder benchmark environment.
# The whole native C/C++ stack runs in one container: gcc, clang, cmake, make,
# and libomp. No GPU/systemd/X.
FROM bench-base:ubuntu-24.04

# [environment] declares cpus = 4, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=4 \
    MKL_NUM_THREADS=4 \
    OPENBLAS_NUM_THREADS=4 \
    NUMEXPR_NUM_THREADS=4

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential g++ clang cmake make gcc libomp-dev llvm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/