FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN python3 -m pip install --no-cache-dir numpy scipy

WORKDIR /app

# All working files are created by the agent during the session
# (/app/integrate.py, /app/eig.py, /app/bench.py). Nothing is baked in here.