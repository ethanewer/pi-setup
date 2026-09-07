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

# Pinned ML toolchain used by the trainer.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1

COPY files/ /app/

# Fixtures are read-only inputs for the task.
RUN chmod -R a-w /app/data /app/train_config.txt \
    && rm -rf /app/tools
