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

# The platform preinstalls the pinned ML toolchain. These versions are the
# immutable baseline: provisioning must NEVER upgrade, downgrade, or remove
# them (offline_load.py depends on them).
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1

# Chain-query helper source (installed into a venv by provision.sh) and the
# offline load-path consumer that pins the ML toolchain.
COPY files/ /app/
