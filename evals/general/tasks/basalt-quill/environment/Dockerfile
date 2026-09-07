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

# scientific python stack for spectra fitting + astropy compound models
RUN pip install --no-cache-dir numpy scipy astropy sympy

# R runtime for the adaptive-rejection-sampling component
RUN apt-get update \
 && apt-get install -y --no-install-recommends r-base \
 && rm -rf /var/lib/apt/lists/*

# fixtures the agent works from
COPY files/ /app/