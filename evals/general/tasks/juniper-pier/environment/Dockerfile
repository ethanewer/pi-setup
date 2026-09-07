# Juniper Pier — Bayesian statistical modeling (PyStan posterior + penalty selection)
FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# PyStan's httpstan backend compiles the model extension with a C++ compiler
# on first use inside the container.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends g++ make \
    && rm -rf /var/lib/apt/lists/*

# numpy/scipy: numerics; scikit-learn + pandas: penalty selection engine.
RUN pip install --no-cache-dir \
    numpy scipy scikit-learn pandas pystan

WORKDIR /app

COPY files/ /app/