FROM bench-base:python-3.12

# [environment] declares cpus = 2, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    OPENBLAS_NUM_THREADS=2 \
    NUMEXPR_NUM_THREADS=2

WORKDIR /app

# Numeric/ML stack for the yield-rank modelling pipeline. CPU-only; installs
# finish well inside the build budget.
RUN pip install --no-cache-dir \
        numpy \
        scipy \
        pandas \
        scikit-learn

# Task fixtures: the process-sensor feature matrix and the matching measured
# wafer-yield vector. The deliverable program is authored by the agent in /app,
# not shipped here.
COPY files/ /app/
