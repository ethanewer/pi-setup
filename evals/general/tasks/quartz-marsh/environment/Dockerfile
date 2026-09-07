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

# Platform-pinned ML toolchain (offline at run time; no GPU).
RUN pip install --no-cache-dir --disable-pip-version-check torch==2.13.0

COPY files/ /app/

RUN python3 -c "import json,torch; c=json.load(open('/app/config.json')); assert c['feature_dim']==64 and c['num_classes']==5; print('config-ok', torch.__version__)"
