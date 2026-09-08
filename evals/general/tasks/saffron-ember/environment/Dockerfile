FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# CPU-only torch plus the data stack used by the deliverable and the verifier.
RUN pip install --no-cache-dir --disable-pip-version-check numpy==2.5.3 pandas==3.0.5 \
 && pip install --no-cache-dir --disable-pip-version-check torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

WORKDIR /app

# Build-time fixtures: the deployed base model + one drifted calibration fold.
COPY files/ /app/

# Materialize the base snapshot and the visible fold, then remove the
# generator so the regime rule is not discoverable in the live container.
RUN python3 /app/gen_fixtures.py \
 && rm -f /app/gen_fixtures.py \
 && rm -rf /app/__pycache__
