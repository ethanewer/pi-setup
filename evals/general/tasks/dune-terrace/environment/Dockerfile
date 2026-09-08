FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential \
    >/dev/null && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir numpy==2.5.3 >/dev/null 2>&1

WORKDIR /app

COPY files/ /app/