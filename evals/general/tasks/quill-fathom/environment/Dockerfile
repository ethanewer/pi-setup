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

# CPU-only torch plus the data stack used by the fixtures and the verifier.
RUN pip install --no-cache-dir numpy==2.5.3 pandas==3.0.5 \
 && pip install --no-cache-dir torch==2.14.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Architecture constants shared by the deliverable contract and the verifier.
ENV QUILL_FEATURES=16 QUILL_HIDDEN=24 QUILL_CLASSES=3

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the frozen base checkpoint and the visible press fold at build
# time, then remove the generator (and stray bytecode) so the concrete
# fold-rule parameters are not discoverable inside the live container.
RUN python3 /app/gen_press.py && rm -f /app/gen_press.py && rm -rf /app/__pycache__
