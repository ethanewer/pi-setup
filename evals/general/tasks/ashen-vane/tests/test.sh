#!/usr/bin/env bash
# ashen-vane verifier (executes-deliverable).
# Executes the deliverable /app/bin/edgecheck on hidden cases (and checks the
# /app/src/edgecheck.c source deliverable), enforcing the fixed
# weights-then-image argument order. Writes reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- deliverables present ------------------------------------------------ #
[ -x /app/bin/edgecheck ] || fail "missing/not executable /app/bin/edgecheck"
[ -s /app/src/edgecheck.c ] || fail "missing/empty /app/src/edgecheck.c source deliverable"
if [ -x /app/bin/edgecheck ] && command -v file >/dev/null 2>&1; then
  file -b /app/bin/edgecheck | grep -q ELF || fail "/app/bin/edgecheck is not a native ELF binary"
fi
[ "$reward" -eq 0 ] && { echo "0" > /logs/verifier/reward.txt; echo "final-reward=0"; exit 0; }

# ---- usage / arg-count handling (fixed CLI contract) --------------------- #
if /app/bin/edgecheck >/tmp/av_u0.out 2>/tmp/av_u0.err; then
  fail "zero-arg invocation should exit nonzero"
else
  rc0=$?
  [ "$rc0" -eq 2 ] || fail "zero-arg exit code $rc0 (want 2)"
  grep -q "usage: edgecheck <weights-path> <image-path>" /tmp/av_u0.err || fail "zero-arg stderr lacks usage line"
  [ -s /tmp/av_u0.out ] && fail "zero-arg invocation wrote stdout"
fi
if /app/bin/edgecheck /etc/hostname >/tmp/av_u1.out 2>/dev/null; then
  fail "one-arg invocation should exit nonzero"
else
  [ "$?" -eq 2 ] || fail "one-arg exit code (want 2)"
  [ -s /tmp/av_u1.out ] && fail "one-arg invocation wrote stdout"
fi

# ---- hidden functional cases -------------------------------------------- #
PY=$(cat <<'PY'
import glob, json, os, re, subprocess, sys

BIN = "/app/bin/edgecheck"
fails = []
cases = sorted(glob.glob("/tests/hidden/*"))
if not cases:
    fails.append("NO HIDDEN CASES")
for d in cases:
    cj = os.path.join(d, "case.json")
    wfn, ifn = os.path.join(d, "weights.txt"), os.path.join(d, "image.pgm")
    if not (os.path.isfile(cj) and os.path.isfile(wfn) and os.path.isfile(ifn)):
        fails.append(f"{d}: missing case.json/weights.txt/image.pgm"); continue
    try:
        spec = json.load(open(cj))
    except Exception as e:
        fails.append(f"{d}: case.json unreadable: {e}"); continue
    mode = spec.get("mode", "run")

    def run(a, b):
        try:
            return subprocess.run([BIN, a, b], capture_output=True, text=True, timeout=60)
        except Exception as e:
            return None

    if mode == "run":
        r = run(wfn, ifn)
        if r is None:
            fails.append(f"{d}: invocation crashed"); continue
        if r.returncode != spec.get("expect_exit", 0):
            fails.append(f"{d}: rc {r.returncode} want {spec.get('expect_exit')}")
            continue
        m = re.fullmatch(r"score=(-?\d+\.\d{2})\n?", r.stdout)
        if not m:
            fails.append(f"{d}: stdout {r.stdout!r} not 'score=<x.xx>'")
            continue
        got = float(m.group(1))
        want = float(spec["expect_score"])
        if abs(got - want) > 0.011:
            fails.append(f"{d}: score {got} want {want}")
    elif mode == "swap":
        r = run(ifn, wfn)
        if r is None:
            fails.append(f"{d}: swapped invocation crashed"); continue
        if r.returncode == 0:
            fails.append(f"{d}: swapped args accepted (rc 0)")
        if r.stdout != "":
            fails.append(f"{d}: swapped args wrote stdout {r.stdout!r}")
    elif mode == "badinput":
        r = run(wfn, ifn)
        if r is None:
            fails.append(f"{d}: bad-input invocation crashed"); continue
        if r.returncode == 0:
            fails.append(f"{d}: malformed input accepted (rc 0)")
        if r.stdout != "":
            fails.append(f"{d}: malformed input wrote stdout {r.stdout!r}")
        if not r.stderr.startswith("error:"):
            fails.append(f"{d}: stderr {r.stderr!r} lacks 'error:' prefix")

if fails:
    print(" ; ".join(fails)); sys.exit(1)
print("HIDDEN-CASES-PASS"); sys.exit(0)
PY
)
if python3 -c "$PY"; then :; else fail "hidden functional checks failed"; fi

echo "final-reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
