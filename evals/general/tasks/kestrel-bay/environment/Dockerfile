FROM bench-base:python-3.12

# [environment] declares cpus = 2, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    OPENBLAS_NUM_THREADS=2 \
    NUMEXPR_NUM_THREADS=2

WORKDIR /app

# CPU-only torch for the gloo process group (no GPU in this image).
RUN pip install --no-cache-dir -q torch --index-url https://download.pytorch.org/whl/cpu

# Read-only fixture: the visible tide-gauge dataset.
COPY files/ /app/
RUN mkdir -p /app/data && mv /app/tide_gauge.csv /app/data/tide_gauge.csv
