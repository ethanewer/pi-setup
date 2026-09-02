#!/bin/bash
# Verifier for river-ledger.
# Executes the /app/solve.py deliverable against the visible journal and against
# hidden cases under /tests/hidden, comparing produced state/audit to embedded
# references. Always writes /logs/verifier/reward.txt (0 or 1).
set -u

mkdir -p /logs/verifier
reward=0
SOLVE=/app/solve.py

[ -f "$SOLVE" ] || { echo "0" > /logs/verifier/reward.txt; exit 0; }

PASS=1
fail() { echo "FAIL: $1"; PASS=0; }

compare() { # expected_state expected_audit produced_state produced_audit
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys

def load_state(p):
    with open(p) as f:
        return json.load(f)

def load_audit(p):
    out = []
    with open(p) as f:
        for ln in f:
            ln = ln.strip()
            if ln:
                out.append(json.loads(ln))
    return out

def norm(x):
    if isinstance(x, (int, float)) and not isinstance(x, bool):
        f = float(x)
        return int(f) if f.is_integer() else f
    if isinstance(x, dict):
        return {k: norm(v) for k, v in x.items()}
    if isinstance(x, list):
        return [norm(i) for i in x]
    return x

es = norm(load_state(sys.argv[1]))
ea = norm(load_audit(sys.argv[2]))
gs = norm(load_state(sys.argv[3]))
ga = norm(load_audit(sys.argv[4]))
assert es == gs, ("STATE", es, gs)
assert ea == ga, ("AUDIT", ea, ga)
PY
}

run_case() { # name input_jsonl want_state want_audit
  local name="$1" input_jsonl="$2" want_state="$3" want_audit="$4"
  local out_dir="/tmp/out_$name"
  mkdir -p "$out_dir"
  local got_state="$out_dir/state.json" got_audit="$out_dir/audit.jsonl"
  if ! python3 "$SOLVE" "$input_jsonl" "$got_state" "$got_audit" >/dev/null 2>&1; then
    fail "deliverable did not run on $name"; return
  fi
  if ! compare "$want_state" "$want_audit" "$got_state" "$got_audit"; then
    fail "wrong result on $name"
  fi
}

# Visible case via explicit CLI args.
run_case visible /app/events.jsonl /tests/expected/state.json /tests/expected/audit.jsonl

# Default-argument invocation must produce /app/state.json and /app/audit.jsonl.
if python3 "$SOLVE" >/dev/null 2>&1; then
  if ! compare /tests/expected/state.json /tests/expected/audit.jsonl \
      /app/state.json /app/audit.jsonl; then
    fail "default-arg output mismatch"
  fi
else
  fail "default-arg invocation failed"
fi

# Hidden cases (fresh journals, fresh numbers, edge/malformed inputs).
run_case case1 /tests/hidden/case1/input.jsonl /tests/hidden/case1/state.json /tests/hidden/case1/audit.jsonl
run_case case2 /tests/hidden/case2/input.jsonl /tests/hidden/case2/state.json /tests/hidden/case2/audit.jsonl
run_case case3 /tests/hidden/case3/input.jsonl /tests/hidden/case3/state.json /tests/hidden/case3/audit.jsonl

[ "$PASS" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt