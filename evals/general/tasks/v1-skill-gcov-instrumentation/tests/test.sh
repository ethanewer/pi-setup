#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=0
if [ -f /app/coverage.json ]; then
  python3 - <<'PYEOF'
import re, json, subprocess, shutil, os

# Build a fresh instrumented copy and let gcov print the file-coverage summary.
d = "/tmp/gcovtest"
shutil.rmtree(d, ignore_errors=True)
os.makedirs(d, exist_ok=True)
shutil.copy("/app/program.c", os.path.join(d, "program.c"))
subprocess.run(["gcc", "-ftest-coverage", "-fprofile-arcs", "program.c", "-o", "program"],
               cwd=d, capture_output=True)
subprocess.run(["./program"], cwd=d, capture_output=True)
r = subprocess.run(["gcov", "program.c"], cwd=d, capture_output=True, text=True)
out = r.stdout
m = re.search(r'Lines executed:([0-9.]+)% of ([0-9]+)', out)
assert m, out
expected = round(float(m.group(1)), 1)

got = json.load(open('/app/coverage.json'))['coverage_percent']
assert isinstance(got, (int, float))
assert abs(float(got) - expected) < 0.06, (got, expected)
# The task's program never executes the `t > 100` branch, so coverage is < 100%.
assert float(got) < 100.0 - 1e-9, got
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt