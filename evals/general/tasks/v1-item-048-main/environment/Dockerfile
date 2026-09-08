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

RUN pip install --no-cache-dir numpy==2.5.3 \
 && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch==2.14.0+cpu --break-system-packages \
 && pip install --no-cache-dir sentence-transformers==6.0.1

COPY files/ /app/