FROM bench-base:python-3.12

# [environment] declares cpus = 2, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    OPENBLAS_NUM_THREADS=2 \
    NUMEXPR_NUM_THREADS=2

# numpy for the bulk cipher search; gcc as an alternative compiled-search path.
RUN python3 -m pip install --no-cache-dir numpy >/dev/null 2>&1 && \
    python3 -c "import numpy; print('numpy', numpy.__version__)" && \
    (command -v gcc >/dev/null || apt-get update >/dev/null 2>&1 && \
     DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       gcc >/dev/null 2>&1 && rm -rf /var/lib/apt/lists/* || true)

WORKDIR /app

COPY files/ /app/
