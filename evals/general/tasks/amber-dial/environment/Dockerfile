FROM bench-base:python-3.12

WORKDIR /app

# Python numeric/ML stack + the small web framework used by the /classify
# endpoint. The wheel that actually resolves here is a CUDA build
# (torch 2.13.0+cu130), not the CPU build this comment used to claim; it runs on
# CPU fine, but it is large and it picks its intra-op thread count from the host
# core count rather than from the container's CPU quota.
RUN pip install --no-cache-dir \
        torch \
        numpy \
        flask

# [environment] declares cpus = 1, which Docker implements as a CFS quota and
# NOT as a CPU-affinity mask: the process still sees all 64 host cores, so torch
# defaults to 32 intra-op threads and then thrashes them against one CPU's worth
# of runtime. Measured in this image with the task's own oracle, train_engine's
# 320 steps took 519.8s that way against 1.6s with a single thread -- a 325x
# penalty that blows straight through the verifier's 180s per-invocation budget,
# so the reference solution could not pass and neither could any agent that wrote
# an ordinary torch training loop. Pin the thread pools to the declared CPU
# budget. This is a property of the environment, not of any particular solution,
# so it is set here once rather than left for each agent to rediscover.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# The task is authored entirely by the agent; there are no binary fixtures.
# This COPY keeps the layer so future fixtures can be added without a rebuild.
COPY files/ /app/