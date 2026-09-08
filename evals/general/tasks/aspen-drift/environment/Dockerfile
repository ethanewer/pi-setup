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

# CPU-only torch plus the data stack used by the pipeline and the verifier.
RUN pip install --no-cache-dir --disable-pip-version-check numpy==2.5.3 pandas==3.0.5 \
 && pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 --index-url https://download.pytorch.org/whl/cpu

# Architecture constants shared by trainer, evaluator and verifier.
ENV ASPEN_FEATURES=6 ASPEN_WIDTH=24 ASPEN_CLASSES=1

# Provided fixtures (train/holdout CSVs).
COPY files/ /app/
