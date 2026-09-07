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

# Exact-optimization stack (scipy ships scipy.optimize.milp backed by HiGHS).
RUN pip install --quiet --no-cache-dir --no-warn-script-location scipy==1.13.1

# Visible weighted Max-SAT instance (read-only fixture).
COPY files/ /app/instances/
RUN chmod -R a-w /app/instances
