FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
# tundra-keystone: concurrency & parallel-execution gap task.
# CPU-only torch (loopback/gloo build) + numpy; small image.
RUN pip install --no-cache-dir --quiet numpy \
 && pip install --no-cache-dir --quiet torch --index-url https://download.pytorch.org/whl/cpu
WORKDIR /app