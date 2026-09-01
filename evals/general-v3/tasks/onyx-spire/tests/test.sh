#!/bin/bash
# Verifier for onyx-spire: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app inputs, and EXECUTES
# the deliverable program (/app/export_rows.py) on the visible case and on every
# hidden case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction tells
# the agent not to modify these; tampering defeats the visible-case check).
PRISTINE_MANIFEST_SHA="33ea6f09633efe6ac587eded5aa3fff51c50000af5870c40a29d62defc4b1035"
PRISTINE_JOB_SHA="f3868cfd7570e3e99053ca7ebd3f3025387e4f4025ec1d02a5a9e9da86ec97b7"

no_modify_broken=0
for pair in "/app/manifest.jsonl:$PRISTINE_MANIFEST_SHA" "/app/job.txt:$PRISTINE_JOB_SHA"; do
    f="${pair%%:*}"; want="${pair##*:}"
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$f" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $f was modified" >&2
            no_modify_broken=1
        fi
    fi
done

export no_modify_broken
python3 - <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/export_rows.py"
no_modify_broken = int(os.environ["no_modify_broken"])


def read_jsonl(path):
    out = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            out.append(json.loads(line))
    return out


def eq(a, b, where):
    if isinstance(a, float) and isinstance(b, float):
        if abs(a - b) > 1e-9:
            raise AssertionError("float mismatch at %s: %r vs %r" % (where, a, b))
        return
    if isinstance(a, dict) and isinstance(b, dict):
        assert set(a.keys()) == set(b.keys()), "key mismatch at %s: %r vs %r" % (where, sorted(a), sorted(b))
        for k in a:
            eq(a[k], b[k], where + "." + str(k))
        return
    if isinstance(a, list) and isinstance(b, list):
        assert len(a) == len(b), "length mismatch at %s: %d vs %d" % (where, len(a), len(b))
        for i, (x, y) in enumerate(zip(a, b)):
            eq(x, y, where + "[%d]" % i)
        return
    assert a == b, "value mismatch at %s: %r vs %r" % (where, a, b)


def run_case(dataset, job, expected_path):
    out = "/tmp/onyx_spire_verify_out.jsonl"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, dataset, job, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        got = read_jsonl(out)
        want = read_jsonl(expected_path)
        eq(got, want, "root")
        return True
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/export_rows.py")
else:
    # --- visible case: EXECUTE export_rows.py on the live supplied inputs ---
    if not (os.path.isfile("/app/manifest.jsonl") and os.path.isfile("/app/job.txt")):
        failures.append("visible inputs missing")
    elif not run_case("/app/manifest.jsonl", "/app/job.txt", "/tests/expected.jsonl"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.jsonl must match expected ---
    if os.path.isfile("/app/answer.jsonl"):
        try:
            got = read_jsonl("/app/answer.jsonl")
            want = read_jsonl("/tests/expected.jsonl")
            eq(got, want, "answer")
        except Exception:
            failures.append("answer.jsonl does not match visible expected")
    else:
        failures.append("missing /app/answer.jsonl")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            dataset = os.path.join(base, "dataset.jsonl")
            job = os.path.join(base, "job.txt")
            exp = os.path.join(base, "expected.jsonl")
            if not all(os.path.isfile(p) for p in (dataset, job, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(dataset, job, exp):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
