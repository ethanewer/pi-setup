#!/bin/bash
set -euo pipefail

# Write the pytest test file with the *correct* expectation.
cat > /app/test_calc.py <<'PYEOF'
import calc

def test_add():
    assert calc.add(2, 3) == 5

def test_multiply():
    assert calc.multiply(4, 5) == 20

def test_divide_float_quotient():
    assert calc.divide(7, 2) == 3.5
PYEOF

# Fix the buggy function.
cat > /app/calc.py <<'PYEOF'
def add(a, b):
    return a + b

def multiply(a, b):
    return a * b

def divide(a, b):
    return a / b
PYEOF

# Ensure tests pass from /app.
cd /app
python3 -m pytest test_calc.py -q >/dev/null
echo "pytest passed"