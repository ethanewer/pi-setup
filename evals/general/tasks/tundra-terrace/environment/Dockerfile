FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# Minimal dependencies: the engine reconstruction must be dependency-free
# (numpy only, no torch/triton). Corporate CA is baked into the base image.
RUN pip install --no-cache-dir numpy==2.5.3

WORKDIR /app
COPY files/ /app/