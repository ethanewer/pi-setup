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
RUN pip install --no-cache-dir numpy==2.5.3 pandas==3.0.5 \
 && pip install --no-cache-dir torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the base snapshot and the visible fold at build time, keep a
# pristine copy for the verifier's no-modify check, then remove the generator
# so the concrete data-generation rule is not discoverable in the container.
RUN python3 /app/gen_data.py \
 && rm -f /app/gen_data.py && rm -rf /app/__pycache__ \
 && mkdir -p /opt/pristine \
 && cp /app/base_snapshot.pt /app/data/line_fold.csv /opt/pristine/

# The agent must never find tests/ or solution/ inside the image.
