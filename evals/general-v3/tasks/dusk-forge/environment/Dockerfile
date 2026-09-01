# dusk-forge: edge sensor-calibration model environment
FROM bench-base:python-3.12

RUN pip install --quiet --no-cache-dir numpy==2.2.6

WORKDIR /app

COPY files/gen_data.py /opt/forge/gen_data.py

# Deterministic fixtures: training table + held-out eval (fixed seeds).
RUN mkdir -p /opt/forge/data \
 && python3 /opt/forge/gen_data.py /opt/forge/data \
 && python3 -c "import numpy as np; d=np.load('/opt/forge/data/train.npz'); assert d['X'].shape==(4096,24) and d['y'].shape==(4096,)"
