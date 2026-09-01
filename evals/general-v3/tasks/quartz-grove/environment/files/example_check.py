#!/usr/bin/env python3
"""
Quartz Grove example_check -- the reference example that must run cleanly inside
the freshly installed, pinned virtual environment.

It proves three things:
  1. numpy, pandas and scipy are all IMPORTABLE from the active interpreter.
  2. every installed version equals the exact `==` pin declared in
     /app/requirements.txt.
  3. a genuine numeric workload runs end to end.

On any failure it prints a diagnostic and exits non-zero.  On success it prints
exactly one success line whose signature (sig) is derived from the session token
and the three actual installed versions, so a hand-written .log can never match.
"""
import hashlib
import os
import sys

def die(msg):
    print(f"QUARTZ_GROVE_FAIL {msg}", flush=True)
    sys.exit(2)

try:
    import numpy
    import pandas
    import scipy
except Exception as exc:  # pragma: no cover
    die(f"import error: {exc}")

PIN_PATH = "/app/requirements.txt"
pins = {}
try:
    for raw in open(PIN_PATH):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "==" not in line:
            die(f"unpinned line in requirements.txt: {line}")
        name, ver = line.split("==", 1)
        pins[name.strip()] = ver.strip()
except OSError as exc:
    die(f"cannot read {PIN_PATH}: {exc}")

installed = {
    "numpy": numpy.__version__,
    "pandas": pandas.__version__,
    "scipy": scipy.__version__,
}
for lib, ver in installed.items():
    want = pins.get(lib)
    if want is None:
        die(f"{lib} is not pinned in requirements.txt")
    if ver != want:
        die(f"pin mismatch {lib}: pinned={want} installed={ver}")

# Real numeric workload exercising all three libraries.
A = numpy.array([[2.0, 0.0], [0.0, 2.0]])
x = numpy.linalg.solve(A, numpy.array([4.0, 6.0]))
if abs(x[0] - 2.0) > 1e-9 or abs(x[1] - 3.0) > 1e-9:
    die("numpy solve is wrong")
frame = pandas.DataFrame({"t": [1.0, 2.0, 3.0]})
if float(frame["t"].sum()) != 6.0:
    die("pandas sum is wrong")
det = scipy.linalg.det(numpy.identity(3))
if abs(det - 1.0) > 1e-9:
    die("scipy linalg is wrong")

session = os.environ.get("QUARTZ_GROVE_SESSION", "")
joined = "|".join([session, installed["numpy"], installed["pandas"], installed["scipy"]])
sig = hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]
print(f"QUARTZ_GROVE_OK sig={sig}", flush=True)