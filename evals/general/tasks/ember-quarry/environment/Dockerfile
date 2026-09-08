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

# Numerics for the MIL forward pass: numpy for the fixture bags, CPU-only torch
# for the model (no GPU in this image).
RUN pip install --no-cache-dir -q numpy==2.5.3 && \
    pip install --no-cache-dir -q torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Read-only visible fixture: the station config and its sensor bag.
COPY files/ /app/

# /app/input/bag.npz layout expected by the CLI contract.
RUN mkdir -p /app/input && mv /app/bag.npz /app/input/bag.npz
