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

# The numeric inference toolchain (CPU-only). torch/transformers/tokenizers are
# used at *build* time to synthesize the local checkpoints, and again at runtime
# by the deliverable /app/infer.py. numpy is a light dependency for fixtures.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 transformers==5.16.1 tokenizers numpy

# Copy the fixture-builder source, then run it to synthesize all immutable
# assets (the local causal-LM checkpoint, the BPE tokenizer, and the HearthNet
# game-evaluation weights) at BUILD time. The build is fully offline afterwards.
COPY files/ /app/
RUN python3 -B /app/_build/build_assets.py

# Drop the one-shot builder + authoring corpus; everything the agent needs is
# the (now deterministic) assets under /app/models, /app/tokenizers,
# /app/weights and /app/job.json.
RUN rm -rf /app/_build