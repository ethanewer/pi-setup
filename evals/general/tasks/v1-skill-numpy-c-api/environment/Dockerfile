FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

WORKDIR /app

# C compiler toolchain for building the C extension.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev g++ libc6-dev make && rm -rf /var/lib/apt/lists/*

# NumPy headers + build tools.
RUN pip install --disable-pip-version-check numpy setuptools wheel