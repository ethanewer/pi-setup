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

RUN pip install --disable-pip-version-check numpy==2.5.3 scipy==1.18.1

RUN cat > /app/objective.py <<'PYEOF'
def objective(x):
    """Convex quadratic in two variables. Global minimum is strictly inside the box."""
    x0, x1 = float(x[0]), float(x[1])
    return (x0 - 2.5) ** 2 + (x1 + 1.25) ** 2
PYEOF