#!/bin/bash
# Verifier for iris-quarry: EXECUTES the deliverable /app/classify.py on the
# visible fixtures and on every hidden generalization case, comparing labels
# exactly and probabilities within tolerance. Writes 1/0 to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
REWARD=0
CLS=/app/classify.py
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

python3 - "$CLS" <<'PY' && REWARD=1
import json
import math
import os
import subprocess
import sys

CLS = sys.argv[1]
failures = []


def norm_probs(ps):
    out = []
    for row in ps:
        try:
            r = [float(v) for v in row]
        except Exception:
            raise AssertionError("probs row not numeric: %r" % (row,))
        out.append(r)
    return out


def compare(got_path, expected_path):
    with open(expected_path) as f:
        want = json.load(f)
    if not os.path.isfile(got_path):
        raise AssertionError("output file missing")
    with open(got_path) as f:
        got = json.load(f)
    if not isinstance(got, dict) or set(got.keys()) != {"labels", "probs"}:
        raise AssertionError("bad output keys: %r" % (list(got) if isinstance(got, dict) else got,))
    labels, probs = got["labels"], got["probs"]
    if not isinstance(labels, list) or not all(isinstance(v, int) for v in labels):
        raise AssertionError("labels not a list of ints")
    if len(labels) != len(want["labels"]) or labels != want["labels"]:
        raise AssertionError("labels mismatch: got %r want %r" % (labels, want["labels"]))
    probs = norm_probs(probs)
    if len(probs) != len(want["probs"]):
        raise AssertionError("probs length mismatch")
    for i, (g, w) in enumerate(zip(probs, want["probs"])):
        if len(g) != len(w):
            raise AssertionError("probs[%d] width mismatch" % i)
        for j, (gv, wv) in enumerate(zip(g, w)):
            if abs(gv - wv) > 2e-6:
                raise AssertionError("probs[%d][%d] %.9f != %.9f" % (i, j, gv, wv))


def run_case(net, samples, expected_path, tag):
    out = os.path.join("/tmp", "irisq_out_%s.json" % tag)
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, CLS, net, samples, out],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        failures.append("case %s crashed: %s" % (tag, e))
        return
    if r.returncode != 0:
        failures.append("case %s non-zero exit: %s" % (tag, r.stderr[-300:]))
        return
    try:
        compare(out, expected_path)
    except AssertionError as e:
        failures.append("case %s: %s" % (tag, e))


if not os.path.isfile(CLS):
    failures.append("missing /app/classify.py")
else:
    # visible case
    if not (os.path.isfile("/app/network.txt") and os.path.isfile("/app/samples.txt")):
        failures.append("visible fixtures missing")
    else:
        run_case("/app/network.txt", "/app/samples.txt", "/tests/expected.json", "visible")

    # visible-case deliverable: /app/predictions.json must match too
    try:
        compare("/app/predictions.json", "/tests/expected.json")
    except AssertionError as e:
        failures.append("predictions.json: %s" % e)
    except Exception as e:
        failures.append("predictions.json unreadable: %s" % e)

    # hidden generalization cases
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden)
                       if os.path.isdir(os.path.join(hidden, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden, c)
            files = [os.path.join(base, f) for f in ("network.txt", "samples.txt", "expected.json")]
            if not all(os.path.isfile(p) for p in files):
                failures.append("hidden case %s malformed" % c)
                continue
            run_case(files[0], files[1], files[2], c)
    else:
        failures.append("no hidden case dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

echo "$REWARD" > /logs/verifier/reward.txt
exit 0
