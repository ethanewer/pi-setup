FROM bench-base:python-3.12

# Simulation-studio authoring bench for drift-atlas.
# numpy/scipy: neuron cable integration; rdkit: descriptor chemistry;
# mujoco: tuned-model simulation (CPU only, no plugins, no rendering).
RUN pip install --no-cache-dir numpy scipy rdkit mujoco >/dev/null 2>&1 && \
    python3 -c "import numpy, scipy, rdkit, mujoco"

WORKDIR /app

# Shipped fixture set: neuron morphology/stimulus, sample molecules,
# the Atlas-Red corewars engine + tournament holdouts, and the reference
# MuJoCo model that must remain byte-identical after tuning.
COPY files/ /app/
COPY files/ref-model.xml /opt/pristine/ref-model.xml
COPY files/corewar/ /opt/pristine/corewar/

ENV PYTHONUNBUFFERED=1