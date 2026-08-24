#!/bin/bash
# Verifier for item-055-main: independently compile+run all four engines over a
# fixed input set, check error behaviors, and require the harness artifacts.
mkdir -p /logs/verifier
reward=0

BASE=/app/polyglot
MC=$BASE/main.c
MR=$BASE/main.rs
FIX=$BASE/expected_fib.txt

if [ -f "$MC" ] && [ -f "$MR" ] && [ -f "$BASE/run_checks.py" ]; then
  # Recompile each engine into /tmp (independent of anything the agent built).
  build_py=1
  C_BIN=/tmp/vf_cm; CPP_BIN=/tmp/vf_cpp; R_BIN=/tmp/vf_rust
  build_c=0; build_cpp=0; build_r=0
  gcc "$MC" -o "$C_BIN" && build_c=1
  g++ -x c++ "$MC" -o "$CPP_BIN" && build_cpp=1
  rustc "$MR" -o "$R_BIN" && build_r=1

  if [ "$build_c" = "1" ] && [ "$build_cpp" = "1" ] && [ "$build_r" = "1" ]; then
    if python3 - <<'PYEOF'
import json, subprocess, sys

MC="/app/polyglot/main.c"
MR="/app/polyglot/main.rs"
FIX="/app/polyglot/expected_fib.txt"
CM="/tmp/vf_cm"
CPP="/tmp/vf_cpp"
RVM="/tmp/vf_rust"

engines = {
    "python": ["python3", MC],
    "c": [CM],
    "cpp": [CPP],
    "rust": [RVM],
}

def run(cmd, arg=None):
    c = list(cmd)
    if arg is not None:
        c.append(arg)
    p = subprocess.run(c, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

rows = []
for line in open(FIX):
    line = line.strip()
    if not line:
        continue
    n, w = line.split()
    rows.append((int(n), int(w)))

# Additional fixed inputs exercised independently by the grader.
extra = [(3, 2), (5, 5), (8, 21), (43, 433494437), (50, 12586269025)]

for name, cmd in engines.items():
    for n, want in rows + extra:
        rc, out, _ = run(cmd, str(n))
        if rc != 0 or out != str(want):
            raise SystemExit("ENGINE %s fib(%d) mismatch: rc=%d out=%r" % (name, n, rc, out))
    for bad in (None, "abc", "-1"):
        rc, out, err = run(cmd, bad)
        if rc == 0 or not err.strip():
            raise SystemExit("ENGINE %s error case %r failed: rc=%d err=%r" % (name, bad, rc, err))

import os
if os.path.isfile("/app/polyglot/status.txt"):
    if open("/app/polyglot/status.txt").read().strip() != "PASS":
        raise SystemExit("status.txt is not PASS")
else:
    raise SystemExit("status.txt missing")

print("ALL FOUR ENGINES PASS")
raise SystemExit(0)
PYEOF
    then
      reward=1
    fi
  fi
fi

echo "$reward" > /logs/verifier/reward.txt