#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/args.py" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, subprocess, sys

APP = sys.argv[1]
ARGS = APP + "/args.py"
OUT = APP + "/parsed.json"

def run(args):
    return subprocess.run([sys.executable, ARGS, *args],
                          capture_output=True, text=True, timeout=30)

def check_ok(args, exp):
    """Invocation must succeed and leave parsed.json equal to exp."""
    r = run(args)
    if r.returncode != 0:
        return False
    try:
        got = json.load(open(OUT))
    except Exception:
        return False
    return got == exp

def check_reject(args):
    """Unknown option / missing value must exit non-zero."""
    r = run(args)
    return r.returncode != 0

# The two invocations stipulated by the task contract:
inv1 = check_ok(["--mode", "fast", "-c", "7", "--label=two words", "/tmp/file1.txt"],
                {"mode": "fast", "count": 7, "label": "two words", "file": "/tmp/file1.txt"})
inv2 = check_ok(["--mode", "slow", "--count", "3", "--label", "no-spaces", "other.txt"],
                {"mode": "slow", "count": 3, "label": "no-spaces", "file": "other.txt"})
# Interleaved positional + options / short forms (contract items 1-3):
inv3 = check_ok(["probe.txt", "-m", "slow", "--label", "probe", "--count", "42"],
                {"mode": "slow", "count": 42, "label": "probe", "file": "probe.txt"})
# Rejection behavior (contract item 4):
rej = check_reject(["--bogus", "x", "f"]) and check_reject(["--mode"])

sys.exit(0 if (inv1 and inv2 and inv3 and rej) else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt