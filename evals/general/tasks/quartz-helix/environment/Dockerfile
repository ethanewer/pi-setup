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

# Data-wrangling toolchain for the quartz-helix data-mart close-out.
RUN pip install --no-cache-dir --quiet pandas numpy

# Shipped workbench fixtures (same schema as the hidden cases) so the agent
# can develop and self-test the transforms locally.
COPY files/ /app/

WORKDIR /app
