#!/usr/bin/env bash
set -euo pipefail

cat > /app/setup.py <<'PY_END'
from setuptools import setup, Extension

setup(
    name="numc",
    ext_modules=[Extension("numc", sources=["numc.c"])],
)
PY_END

cd /app
python setup.py build_ext --inplace

cat > /app/out.json <<'JSON_END'
{"add": 42, "mul": 42.0}
JSON_END

python3 - <<'PY_END'
import json, sys
sys.path.insert(0, "/app")
import numc
assert numc.add(30, 12) == 42
assert abs(numc.mul(6.0, 7.0) - 42.0) < 1e-9
d = json.load(open("/app/out.json"))
assert d == {"add": 42, "mul": 42.0}
PY_END