FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check numpy scipy

RUN cat > /app/objective.py <<'PYEOF'
def objective(x):
    """Convex quadratic in two variables. Global minimum is strictly inside the box."""
    x0, x1 = float(x[0]), float(x[1])
    return (x0 - 2.5) ** 2 + (x1 + 1.25) ** 2
PYEOF