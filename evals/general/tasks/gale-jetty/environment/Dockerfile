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

# Data tooling for the pipeline (csv/json/parquet parsing + numpy matrices).
RUN python -m pip install --no-cache-dir numpy==2.5.3 pandas==3.0.5 pyarrow==25.0.1

COPY files/ /app/.fixtures/

# Materialize the working fixtures (inbox docs, masks, heterogeneous ledger,
# candidates, config, sequential constant) directly into /app.
RUN python3 /app/.fixtures/build_fixtures.py && rm -rf /app/.fixtures

WORKDIR /app