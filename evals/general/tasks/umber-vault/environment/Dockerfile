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

# CPU-only torch (no CUDA), plus the data/ML stack used by the pipeline and the
# verifier. scikit-learn is pulled for the documented stack even though the core
# deliverable scripts rely on numpy/pandas/torch only.
RUN pip install --no-cache-dir numpy==2.5.3 pandas==3.0.5 scikit-learn==1.9.0 \
 && pip install --no-cache-dir torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Architecture constant shared by every component (must match the verifier).
ENV UMBER_FEATURES=48 UMBER_HIDDEN=64 UMBER_CLASSES=2

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the provided datasets inside /app/data at build time, then remove
# the generator (and any stray bytecode) so the concrete data-generation rule is
# not discoverable inside the live container.
RUN python3 /app/gen_data.py && rm -f /app/gen_data.py && rm -rf /app/__pycache__

# The agent must never find tests/ or solution/ inside the image.