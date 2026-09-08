FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# Simulation-studio authoring bench for drift-atlas.
# numpy/scipy: neuron cable integration; rdkit: descriptor chemistry;
# mujoco: tuned-model simulation (CPU only, no plugins, no rendering).
RUN pip install --no-cache-dir numpy==2.5.3 scipy==1.18.1 rdkit==2026.3.6 mujoco==3.12.0 >/dev/null 2>&1 && \
    python3 -c "import numpy, scipy, rdkit, mujoco"

WORKDIR /app

# Shipped fixture set: neuron morphology/stimulus, sample molecules,
# the Atlas-Red corewars engine + tournament holdouts, and the reference
# MuJoCo model that must remain byte-identical after tuning.
COPY files/ /app/
COPY files/ref-model.xml /opt/pristine/ref-model.xml
COPY files/corewar/ /opt/pristine/corewar/

ENV PYTHONUNBUFFERED=1