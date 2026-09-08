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

RUN pip install --disable-pip-version-check numpy==2.5.3

RUN python3 - <<'PYEOF'
vals = [(i * 13 + 7) % 25 for i in range(50)]
with open('/app/scores.txt', 'w') as f:
    for v in vals:
        f.write(str(v) + '\n')
PYEOF