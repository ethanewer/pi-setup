# quartz-summit - small-scale ML training harness (CPU-only).
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

# ML toolchain used by the deliverable (torch for the 300-dim embedding layer)
# and by the verifier (numpy recomputes the STS / edge expectations). CPU only.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.14.0 \
    numpy==2.5.3 \
    scipy==1.18.1 \
    scikit-learn==1.9.0

COPY files/ /app/
