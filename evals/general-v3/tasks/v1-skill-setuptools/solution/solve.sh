#!/bin/bash
set -euo pipefail

mkdir -p /app/greetpkg

cat > /app/greetpkg/__init__.py <<'PYEOF'
def greet(name="harbor"):
    return "hello " + name
PYEOF

cat > /app/setup.py <<'PYEOF'
from setuptools import setup

setup(
    name="greetpkg-extra",
    version="1.0.0",
    description="setuptools packaging probe",
    packages=["greetpkg"],
)
PYEOF

cd /app && pip install --no-cache-dir --force-reinstall . >/dev/null

cat > /app/write_out.py <<'PYEOF'
import greetpkg
with open("/app/output.txt", "w") as f:
    f.write(greetpkg.greet() + "\n")
PYEOF
python3 /app/write_out.py