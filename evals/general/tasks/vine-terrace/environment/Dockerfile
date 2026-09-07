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
# pin to versions the task was validated against
RUN pip install --no-cache-dir \
      numpy==2.5.2 \
      networkx==3.6.1 \
      jax==0.11.1 \
      jaxlib==0.11.1 \
      jaxley==0.13.0 \
      pytest==9.1.1
COPY files/ /app/
