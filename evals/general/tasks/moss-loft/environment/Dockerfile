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

# CPU training stack: torch for the model/snapshot, numpy for the fixtures.
RUN pip install --no-cache-dir --disable-pip-version-check \
    numpy==2.5.3 \
    torch==2.13.0

# Build-time-only dataset/config generator.
COPY files/ /app/

# Materialize the visible training fixture set, then remove the generator (and
# any stray bytecode) so the concrete data-generation rule is not discoverable
# inside the live container.
RUN python3 /app/gen_data.py \
 && rm -f /app/gen_data.py \
 && rm -rf /app/__pycache__
