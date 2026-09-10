#!/bin/bash
# Verifier for clinker-quay (SWE-bench-shaped debugging task against the real
# sympy tree). Checks, in order:
#   1. the declared deliverable /app/diagnosis.md exists and names the real
#      module and cause (not a placeholder, not a copy of the prompt),
#   2. /app/src is the real cloned tree,
#   3. sympy's OWN targeted submodule test suite (sympy/discrete/) passes,
#   4. every hidden reproducer in /tests/hidden/*/run.py passes. Each hidden
#      case exercises the same code path with fresh inputs against an
#      independently computed expectation.
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

# ---- 1. deliverable: /app/diagnosis.md -------------------------------------
if [ ! -f /app/diagnosis.md ]; then
    echo "FAIL: deliverable /app/diagnosis.md missing" >&2
    failures=1
else
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
ok = (len(text.strip()) >= 100
      and "discrete" in low
      and any(k in low for k in ("twiddle", "omega", "butterfly", "fft", "fourier")))
if not ok:
    print("FAIL: /app/diagnosis.md does not name the real module and cause "
          f"(len={len(text.strip())}, mentions discrete={'discrete' in low}, "
          f"mentions fft/twiddle/omega/butterfly="
          f"{any(k in low for k in ('twiddle','omega','butterfly','fft','fourier'))})", file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (names module+cause)")
PY
    rc=$?
    if [ $rc -ne 0 ]; then
        failures=1
    fi
fi

# ---- 2. this must be the real upstream clone --------------------------------
if [ ! -f /app/src/sympy/discrete/transforms.py ] || [ ! -d /app/src/sympy/core ]; then
    echo "FAIL: /app/src is not the sympy source tree" >&2
    failures=1
fi

# ---- 3. the upstream project's own targeted suite --------------------------
if [ -d /app/src ]; then
    log=/tmp/verifier_dtest.log
    if (cd /app/src && PYTHONPATH=/app/src python3 -m pytest -q sympy/discrete/ -p no:cacheprovider > "$log" 2>&1); then
        echo "sympy own sympy/discrete suite: PASS ($(tail -1 "$log"))"
    else
        echo "FAIL: sympy's own sympy/discrete suite does not pass" >&2
        tail -15 "$log" >&2
        failures=1
    fi
fi

# ---- 4. hidden reproducers (fresh inputs, independent expectations) ---------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.py"
    if [ -f "$run" ]; then
        hlog=/tmp/verifier_hidden.log
        if (cd /app/src && PYTHONPATH=/app/src python3 "$run" > "$hlog" 2>&1); then
            echo "hidden case $(basename "$case_dir"): PASS"
        else
            echo "FAIL: hidden case $(basename "$case_dir") failed" >&2
            tail -6 "$hlog" >&2
            failures=1
        fi
    fi
done

if [ $failures -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: failures present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0