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

# numpy + rdkit from the default index, then CPU-only torch from the PyTorch
# CPU wheel index (no GPU in this image; the #nn module only needs CPU ops).
RUN pip install --no-cache-dir -q numpy==2.5.3 rdkit==2026.3.6 && \
    pip install --no-cache-dir -q torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Read-only fixtures: the word-relation vocabulary and the molecule catalog.
COPY files/ /app/

# Deliverables (created by the agent) live under /app alongside these fixtures.