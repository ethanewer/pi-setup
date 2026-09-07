# dusk-forge: edge sensor-calibration model environment
FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install --quiet --no-cache-dir numpy==2.2.6

WORKDIR /app

COPY files/gen_data.py /opt/forge/gen_data.py

# Deterministic fixtures: training table + held-out eval (fixed seeds).
RUN mkdir -p /opt/forge/data \
 && python3 /opt/forge/gen_data.py /opt/forge/data \
 && python3 -c "import numpy as np; d=np.load('/opt/forge/data/train.npz'); assert d['X'].shape==(4096,24) and d['y'].shape==(4096,)"
