#!/bin/bash
# flint-mantle verifier. Executes /app/solve.py on the visible case and on
# every hidden case, comparing outputs byte-exactly against independent
# expected artifacts. Writes the reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

fail() { echo "flint-mantle FAIL: $1" >&2; }

run_case() {
  # run_case <construct.json> <name> <expected.json> <expected.fasta> <label>
  local construct="$1" name="$2" exp_json="$3" exp_fasta="$4" label="$5"
  local workdir
  workdir="$(mktemp -d)"
  if ! python3 /app/solve.py "$construct" /app/codons.json "$name" \
        "$workdir/answer.json" "$workdir/constructs.fasta" \
        > "$workdir/log" 2>&1; then
    fail "$label: solve.py exited nonzero"
    sed 's/^/    /' "$workdir/log" >&2
    rm -rf "$workdir"
    return 1
  fi
  python3 - "$workdir/answer.json" "$exp_json" "$workdir/constructs.fasta" "$exp_fasta" <<'PY'
import hashlib, json, sys
got_ans, exp_ans, got_fasta, exp_fasta = sys.argv[1:5]
got = json.load(open(got_ans))
exp = json.load(open(exp_ans))
if got != exp:
    print("answer mismatch", file=sys.stderr)
    sys.exit(1)
gb = open(got_fasta, "rb").read()
eb = open(exp_fasta, "rb").read()
if gb != eb:
    print("fasta byte mismatch", file=sys.stderr)
    sys.exit(1)
if got["fasta_sha256"] != hashlib.sha256(gb).hexdigest():
    print("self-reported fasta_sha256 wrong", file=sys.stderr)
    sys.exit(1)
PY
  local rc=$?
  rm -rf "$workdir"
  if [ $rc -ne 0 ]; then
    fail "$label: outputs do not match expected artifacts"
    return 1
  fi
  return 0
}

ok=1

# visible case: deliverables must already exist AND be reproducible
if [ ! -f /app/answer.json ] || [ ! -f /app/constructs.fasta ]; then
  fail "visible deliverables missing"
  ok=0
elif ! run_case /app/construct.json visible /tests/hidden/visible_expected.json \
      /tests/hidden/visible_expected.fasta "visible"; then
  ok=0
fi

for c in a b c; do
  run_case "/tests/hidden/$c/construct.json" "hidden_$c" \
    "/tests/hidden/$c/expected.json" "/tests/hidden/$c/expected.fasta" \
    "hidden-$c" || ok=0
done

# malformed input must produce a nonzero exit, not a crash-and-burn wrong answer
tmpc="$(mktemp)"
echo '{"domains": {"D1": "MK"}, "linkers": {}, "order": ["D1", "NOPE"]}' > "$tmpc"
if python3 /app/solve.py "$tmpc" /app/codons.json bad /tmp/a.json /tmp/a.fasta \
    >/dev/null 2>&1; then
  fail "malformed input: expected nonzero exit"
  ok=0
fi
rm -f "$tmpc" /tmp/a.json /tmp/a.fasta

if [ $ok -eq 1 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "flint-mantle reward=$reward" >&2
