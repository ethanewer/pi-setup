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

# Python ML libs used by the deliverable and the fixtures.
RUN python3 -m pip install --no-cache-dir torch transformers safetensors

# Generate the visible fixtures (/app/pretrained_lm, /app/state_seed.pkl,
# /app/base_clf, /app/data) and the hidden verifier fixtures (/buildout/hidden).
COPY files/fix_gen.py /build/fix_gen.py
RUN python3 /build/fix_gen.py && rm -rf /build

# The agent works in /app and is expected to add /app/workflow.py and
# /app/artifact.
WORKDIR /app