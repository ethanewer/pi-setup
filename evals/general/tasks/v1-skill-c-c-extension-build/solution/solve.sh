#!/usr/bin/env bash
set -euo pipefail

cat > /app/native/setup.py <<'PY_END'
from setuptools import setup, Extension

setup(
    name="quickcalc",
    ext_modules=[
        Extension(
            "quickcalc",
            sources=["libcalc.c", "quickwrap.cpp"],
            language="c++",
        )
    ],
)
PY_END

cd /app/native
python setup.py build_ext --inplace

gcc -O2 -o /app/native/calc_cli /app/native/calc_cli.c /app/native/libcalc.c

python3 - <<'PY_END'
import json, sys
sys.path.insert(0, "/app/native")
import quickcalc
assert quickcalc.add(7, 3) == 10
assert quickcalc.sub(7, 3) == 4
PY_END

test "$(/app/native/calc_cli 7 3)" = "add=10 sub=4"

cat > /app/native/build_report.json <<'JSON_END'
{"extension": "quickcalc", "cli_worked": true}
JSON_END