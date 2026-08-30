FROM bench-base:python-3.12

RUN pip install --no-cache-dir numpy scipy

# The task env is pinned to 1 CPU, but bench-base BLAS defaults to spawning one
# thread per host core. Under a concurrent full-suite sweep that thread
# oversubscription thrashes and stalls the dense eigendecomposition on the
# 1400x1400 fixture. Pin the numeric backends to a single thread so timing is
# predictable and stays well within the verifier timeout.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

WORKDIR /app

COPY files/ /app/
