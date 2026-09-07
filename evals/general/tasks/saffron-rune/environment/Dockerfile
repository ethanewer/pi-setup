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

# numpy for the fixed-size feature arrays; everything else is stdlib.
RUN python3 -m pip install --no-cache-dir --quiet numpy==2.1.3

# Read-only fixture: the molecule catalog (id,smiles CSV, incl. invalid rows).
COPY files/ /app/

CMD ["/bin/bash"]
