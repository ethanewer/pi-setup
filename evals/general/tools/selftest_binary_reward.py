#!/usr/bin/env python3
"""Self-test for tools/check_binary_reward.py.

The gate makes a static claim about every shell/python verifier in the suite, so
it needs fixtures that pin both directions:

  * every fractional-reward shape that has actually shipped in this suite must
    still be flagged, otherwise the gate is quietly permissive
  * every shape that is genuinely binary must pass, including the two that
    produced false positives while the gate was being written: a verifier that
    runs python for its exit code while printing %.4f diagnostics, and a
    binarized ternary sitting in front of a fractional accumulator

Run: python3 tools/selftest_binary_reward.py
"""
from __future__ import annotations

import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_binary_reward as g

TASK_TOML = 'schema_version = "1.4"\n\n[metadata]\ndifficulty = "easy"\n'

# name -> (test.sh, expected verdict)
CASES = {}

# ---------------------------------------------------------------- must flag

CASES['frac-shell-ladder'] = ('''#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/a ]; then reward=1
elif [ -f /app/b ]; then reward=0.5
fi
echo "$reward" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-shell-inline-ladder'] = ('''#!/bin/bash
reward=0
if [ "$a" = "1" ] && [ "$reward" = "1" ]; then reward=1
elif [ "$reward" = "1" ]; then reward=0.6
fi
echo "$reward" > /logs/verifier/reward.txt
''', 'NON_BINARY')

# v1-item-019-main shipped this. The interpreter's stdout is captured whole into
# the reward, and an early-exit path printed a diagnostic to stdout before raising
# SystemExit -- which is a BaseException, so the `except Exception` handler that
# prints 0 never ran. reward.txt received the literal text "recovered db missing".
# The seed extractor used to take the rest of the line, producing a compound string
# no classifier recognised; it now matches parentheses, and a quoted literal that
# is neither 0 nor 1 nor a path is flagged.
CASES['prose-print-into-captured-stdout'] = ('''#!/bin/bash
mkdir -p /logs/verifier
reward=0
ok=$(python3 - <<'PYEOF'
import os, sys
try:
    if not os.path.exists('/app/recovered/orders.db'):
        print('recovered db missing'); raise SystemExit(1)
    print(1)
except Exception:
    print('0')
PYEOF
)
reward=$ok
echo "$reward" > /logs/verifier/reward.txt
''', 'NON_BINARY')

# The same shape with the diagnostic correctly routed to stderr and a numeric
# verdict printed, plus a shell epilogue that refuses to write anything but 0 or 1.
CASES['prose-print-routed-to-stderr'] = ('''#!/bin/bash
mkdir -p /logs/verifier
reward=0
ok=$(python3 - <<'PYEOF'
import os, sys
try:
    if not os.path.exists('/app/recovered/orders.db'):
        print('recovered db missing', file=sys.stderr); print(0); raise SystemExit(1)
    print(1)
except Exception:
    print('0')
PYEOF
)
case "$ok" in
  0|1) reward=$ok ;;
  *) reward=0 ;;
esac
echo "$reward" > /logs/verifier/reward.txt
''', 'BINARY')

CASES['frac-heredoc-fstring'] = ('''#!/bin/bash
score=$(python3 - <<'PY'
score = 0.0
if ok: score = 1.0
elif part: score = 0.6
print(f"{score:.2f}", end="")
PY
)
printf "%s" "$score" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-heredoc-division'] = ('''#!/bin/bash
reward=$(python3 - <<'PY'
reward = 0.0
if total:
    reward = passes / total
print(f"{reward:.2f}")
PY
)
echo "$reward" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-points-over-100'] = ('''#!/bin/bash
points=0
[ "$a" = OK ] && points=$((points+40))
[ "$b" = OK ] && points=$((points+60))
reward=$(python3 -c "print($points / 100.0)")
echo "$reward" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-direct-redirect'] = ('''#!/bin/bash
points=0
[ "$a" = OK ] && points=$((points+100))
python3 -c "print(round($points/100.0, 4))" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-awk-weighted'] = ('''#!/bin/bash
A=0 B=0 C=0 D=0
[ ok ] && A=1
reward=$(awk "BEGIN{print $A*0.25+$B*0.25+$C*0.25+$D*0.25}")
echo "$reward" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-write-repr'] = ('''#!/bin/bash
python3 - <<'PY'
reward = 1.0
if partial:
    reward = 0.5
open("/logs/verifier/reward.txt", "w").write(repr(reward))
PY
''', 'NON_BINARY')

CASES['frac-write-call-helper'] = ('''#!/bin/bash
python3 - <<'PY'
def write(r):
    open("/logs/verifier/reward.txt", "w").write(repr(r))
reward = 1.0
if partial:
    reward = 0.5
write(reward)
PY
''', 'NON_BINARY')

CASES['frac-dict-score'] = ('''#!/bin/bash
score=$(python3 - <<'PY'
STATE = {"score": 0.0}
v = 0.0
if a: v += 0.4
if b: v += 0.6
STATE["score"] = round(min(v, 1.0), 2)
print(f"{STATE['score']:.2f}", end="")
PY
)
printf "%s" "$score" > /logs/verifier/reward.txt
''', 'NON_BINARY')

CASES['frac-weighted-accumulator'] = ('''#!/bin/bash
python3 - <<'PY'
reward = 0.0
if visible_ok:
    reward += 0.5
for case, weight in CASES:
    reward += weight
reward = round(min(reward, 1.0), 4)
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("%.4f\\n" % reward)
PY
''', 'NON_BINARY')

CASES['frac-path-const'] = ('''#!/bin/bash
python3 - <<'PY'
REWARD = "/logs/verifier/reward.txt"
r = 0.5 if partial else 1.0
open(REWARD, "w").write(str(r))
PY
''', 'NON_BINARY')

# ---------------------------------------------------------------- must pass

CASES['bin-literal-echo'] = ('''#!/bin/bash
if [ -f /app/a ]; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
''', 'BINARY')

CASES['bin-shell-var-zero-one'] = ('''#!/bin/bash
reward=0
[ -f /app/a ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
''', 'BINARY')

CASES['bin-branch-one-liner'] = ('''#!/bin/bash
ok=0
[ -f /app/a ] && ok=1
reward=0
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
''', 'BINARY')

CASES['bin-py-ternary'] = ('''#!/bin/bash
python3 - <<'PY'
failures = []
if not ok: failures.append("x")
reward = 0 if failures else 1
open("/logs/verifier/reward.txt", "w").write(str(reward))
PY
''', 'BINARY')

CASES['bin-path-var-helpers'] = ('''#!/bin/bash
REWARD_FILE=/logs/verifier/reward.txt
mkdir -p "$(dirname "$REWARD_FILE")"
fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }
okay() { echo "REWARD-OK: all checks passed" >&2; echo 1 > "$REWARD_FILE"; exit 0; }
[ -f /app/a ] || fail "missing"
okay
''', 'BINARY')

CASES['bin-exit-code-helper-with-diagnostics'] = ('''#!/bin/bash
reward=0
python3 /tests/check.py      || { echo "$reward" > /logs/verifier/reward.txt; exit 1; }
python3 - <<'PY' && reward=1
acc = 0.95
print("%s: eval accuracy %.4f" % ("hidden", acc))
import sys
sys.exit(0 if acc >= 0.90 else 1)
PY
echo "$reward" > /logs/verifier/reward.txt
''', 'BINARY')

CASES['bin-binarized-fstring'] = ('''#!/bin/bash
score=$(python3 - <<'PY'
score = sum(1 for c in checks if ok(c)) / len(checks)
print(1 if (score) >= 1.0 else 0)
PY
)
printf '%s\\n' "$score" > /logs/verifier/reward.txt
''', 'BINARY')

CASES['bin-binarized-write-call'] = ('''#!/bin/bash
python3 - <<'PY'
def write(r):
    open("/logs/verifier/reward.txt", "w").write("1" if (r) >= 1.0 else "0")
reward = 1.0
if partial:
    reward = 0.5
write(reward)
PY
''', 'BINARY')

CASES['bin-binarized-accumulator'] = ('''#!/bin/bash
python3 - <<'PY'
credit = 0.0
if visible_ok:
    credit += 0.5
for case, weight in CASES:
    credit += weight
binary_reward = 1 if credit >= 1.0 else 0
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("%d\\n" % binary_reward)
print("REWARD=%d credit=%.4f" % (binary_reward, credit))
PY
''', 'BINARY')

CASES['bin-binarized-points'] = ('''#!/bin/bash
points=0
[ "$a" = OK ] && points=$((points+40))
[ "$b" = OK ] && points=$((points+60))
reward=$(python3 -c "print(1 if ($points) >= 100 else 0)")
echo "$reward" > /logs/verifier/reward.txt
''', 'BINARY')

CASES['bin-binarized-awk'] = ('''#!/bin/bash
A=0 B=0 C=0 D=0
[ ok ] && A=1
reward=$(awk "BEGIN{print (($A+$B+$C+$D)>=4)?1:0}")
echo "$reward" > /logs/verifier/reward.txt
''', 'BINARY')


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix='binarity-selftest-'))
    failures = []
    try:
        for name, (script, expected) in CASES.items():
            d = tmp / 'tasks' / name
            (d / 'tests').mkdir(parents=True)
            (d / 'task.toml').write_text(TASK_TOML)
            (d / 'tests' / 'test.sh').write_text(script)
            verdict, notes, bad = g.audit_task(d)
            if verdict != expected:
                failures.append((name, expected, verdict, bad, notes))
        total = len(CASES)
        print(f'selftest_binary_reward: {total - len(failures)}/{total} cases pass')
        for name, exp, got, bad, notes in failures:
            print(f'  FAIL {name}: expected {exp}, got {got}')
            for _, w in bad[:3]:
                print(f'       flagged: {w[:110]}')
            for n in notes[:2]:
                print(f'       note: {n}')
        return 1 if failures else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
