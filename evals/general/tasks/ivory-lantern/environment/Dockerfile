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

# numpy: the weights shard and the offline loader both need it. No torch /
# transformers — the loader is a local-artifact reader, not a hub client.
RUN python3 -m pip install --no-cache-dir --quiet numpy==2.1.3

# Read-only deployment files: the offline loader and the scattered upstream
# source tree (manifest + blob shards + distractors) to mirror.
COPY files/ /app/

# The shipped loader must not be modified by the agent.
RUN chmod 0444 /app/load_pretrained.py

CMD ["/bin/bash"]
