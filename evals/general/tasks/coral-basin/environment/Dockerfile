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

# CPU-only torch plus the data stack used by the fixtures and the verifier.
RUN pip install --no-cache-dir numpy==2.5.3 pandas==3.0.5 \
 && pip install --no-cache-dir torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Architecture constants shared by the deliverable contract and the verifier.
ENV CORAL_FEATURES=20 CORAL_HIDDEN=32 CORAL_CLASSES=2

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the frozen triage model and the visible bag file at build time,
# then remove the generator (and stray bytecode) so nothing beyond the frozen
# snapshot itself is discoverable inside the live container.
RUN python3 /app/gen_buoy.py && rm -f /app/gen_buoy.py && rm -rf /app/__pycache__
