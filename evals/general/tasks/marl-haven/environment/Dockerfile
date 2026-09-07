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

# numpy for the .npy matrix deliverable.
RUN python3 -m pip install --no-cache-dir numpy

COPY files/ /app/.fixtures/

# Materialize the visible fixtures (binary SBT-1 capture + query) into /app.
RUN python3 /app/.fixtures/build_fixtures.py && rm -rf /app/.fixtures

WORKDIR /app
