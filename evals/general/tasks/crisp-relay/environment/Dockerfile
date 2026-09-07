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

# The platform pins the ML toolchain exactly. Everything the agent does must
# preserve these two packages bit-for-bit; the offline scorer depends on them.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir --disable-pip-version-check \
    transformers==5.16.1

# The scorer runs fully offline: never touch the network at run or verify time.
ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    HF_DATASETS_OFFLINE=1

COPY files/ /app/
