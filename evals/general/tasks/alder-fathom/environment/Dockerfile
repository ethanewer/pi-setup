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

# Deterministic replay eval of a trained CPU policy: torch (CPU wheel) + numpy.
RUN pip install --no-cache-dir --quiet \
        numpy==2.5.3 && \
    pip install --no-cache-dir --quiet \
        torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Read-only fixture: the rover case (env config + trained checkpoint).
COPY files/ /app/
