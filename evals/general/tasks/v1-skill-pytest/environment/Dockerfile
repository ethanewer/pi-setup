FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir pytest==9.1.1

RUN cat > /app/calc.py <<'PYEOF'
def add(a, b):
    return a + b

def multiply(a, b):
    return a * b

def divide(a, b):
    return a // b  # BUG: should be true division
PYEOF