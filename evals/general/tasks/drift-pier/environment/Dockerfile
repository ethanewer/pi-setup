FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install --no-cache-dir pandas==3.0.5 numpy==2.5.3 >/dev/null 2>&1 && \
    python3 -c "import pandas, numpy"

WORKDIR /app

# Shipped baseline data-mart for the default close-out run.
COPY files/ /app/

ENV PYTHONUNBUFFERED=1