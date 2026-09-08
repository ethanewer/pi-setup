FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install --no-cache-dir \
    scikit-learn==1.9.0 \
    scipy==1.18.1 \
    pandas==3.0.5 \
    hydra-core==1.3.6 \
    joblib==1.6.0 \
    pyyaml==6.0.3

WORKDIR /app
COPY files/ /app/