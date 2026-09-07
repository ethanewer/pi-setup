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

# CPU training stack for the snapshot task (deterministic pinned install).
RUN pip install --no-cache-dir --disable-pip-version-check \
    numpy==2.5.2 \
 && pip install --no-cache-dir --disable-pip-version-check torch==2.13.0

# Provided fixtures: visible run data + config. No solver code is shipped.
COPY files/ /app/

