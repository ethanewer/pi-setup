#!/bin/bash
# Verifier for hazel-quarry: enforces the no-modify rule on /app/data, checks
# the visible deliverables, and EXECUTES /app/lexicon.py on every hidden case
# (fresh corpora, fresh protected lists, fresh thresholds). Writes 0/1 to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_ARIA="5487ff53c2c5ed5f99d6d69e63145ead853c487271d38e04b5603fb982fea291"
PRISTINE_BOREALIS="9ada5bd4416977b98fad81ec6007a9663f67da704ff275711acbab0d06e6d41c"
PRISTINE_REQUIRED="688f388ca6a632c16d0a471966f0c49f788faf9340597bb02f7500a06cb5568a"

no_modify_broken=0
for pair in "corpus_aria.txt:$PRISTINE_ARIA" "corpus_borealis.txt:$PRISTINE_BOREALIS" "required_terms.txt:$PRISTINE_REQUIRED"; do
    f="/app/data/${pair%%:*}"
    want="${pair##*:}"
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

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/lexicon.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible inputs under /app/data modified or missing")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/lexicon.py")
else:
    # --- visible deliverable /app/lexicon.txt must match the visible expected
    if not os.path.isfile("/app/lexicon.txt"):
        failures.append("missing /app/lexicon.txt")
    else:
        try:
            got = open("/app/lexicon.txt", encoding="utf-8").read().split()
            want = json.load(open("/tests/expected.json"))["tokens"]
            if got != want:
                failures.append("/app/lexicon.txt does not match visible expected")
            else:
                # the 30 protected terms must all survive the threshold
                missing = [t for t in want if False]
                req = open("/app/data/required_terms.txt", encoding="utf-8").read().lower().split()
                miss = [t for t in req if t not in got]
                if miss:
                    failures.append("protected terms missing from lexicon.txt: %s" % miss)
                if len(got) < 40:
                    failures.append("visible lexicon too small (%d tokens)" % len(got))
        except Exception as e:
            failures.append("lexicon.txt unreadable: %r" % (e,))

    # --- hidden cases: execute the deliverable on fresh inputs
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden_dir, case)
        params_p = os.path.join(base, "params.json")
        exp_p = os.path.join(base, "expected.json")
        try:
            params = json.load(open(params_p))
            want = json.load(open(exp_p))["tokens"]
        except Exception:
            failures.append("hidden case '%s' has malformed fixture" % case)
            continue
        out = "/tmp/hazel_quarry_out_%s.txt" % case
        cmd = [sys.executable, SOLVE]
        for c in params.get("corpora", []):
            cmd += ["--corpus", os.path.join(base, c)]
        cmd += ["--required", os.path.join(base, params.get("required", "required.txt")),
                "--min-count", str(params.get("min_count", 1)), "--out", out]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        except Exception as e:
            failures.append("hidden '%s' execution error: %r" % (case, e))
            continue
        if r.returncode != 0 or not os.path.exists(out):
            failures.append("hidden '%s' exited %d without output" % (case, r.returncode))
            continue
        try:
            got = open(out, encoding="utf-8").read().split()
        except Exception as e:
            failures.append("hidden '%s' output unreadable: %r" % (case, e))
            continue
        if got != want:
            failures.append("hidden '%s' tokens mismatch" % case)
            continue
        # sanity floor: the true filtered vocabulary is never tiny
        if len(want) < 5:
            failures.append("hidden '%s' unexpected tiny expected vocab" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
