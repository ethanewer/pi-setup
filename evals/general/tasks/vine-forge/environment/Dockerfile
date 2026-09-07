FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# numpy + pandas only (torch is deliberately absent: the scorer ships as .npz
# and streaming inference is numpy work).
RUN pip install --no-cache-dir --disable-pip-version-check numpy pandas

WORKDIR /app

COPY files/ /app/

# Build-time fixtures: the fixed scorer and the visible 8-bag file, generated
# deterministically; the generator is removed so the live container does not
# reveal the exact sampling rule.
RUN python3 /app/gen_fixtures.py \
 && rm -f /app/gen_fixtures.py \
 && rm -rf /app/__pycache__
