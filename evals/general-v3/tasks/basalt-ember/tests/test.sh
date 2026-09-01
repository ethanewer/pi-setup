#!/bin/bash
# Verifier for basalt-ember: enforces the no-modify rule on the supplied /app
# fixtures, checks the visible deliverables, and EXECUTES /app/classify.py on
# every hidden network/samples case. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. All parses are guarded.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_NET_SHA="dac09f3d612b278768432d7ef83179ad951bcc76c71ca2f5dbec608b5a4b567c"
PRISTINE_SAMPLES_SHA="72f137fd76b24a4bbd3cf72bafb56d7128ebba678bb74d78beaaf19c88063086"

no_modify_broken=0
if [ ! -f /app/network.json ]; then
    echo "no-modify: /app/network.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/network.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_NET_SHA" ]; then
        echo "no-modify: /app/network.json was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/samples.json ]; then
    echo "no-modify: /app/samples.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/samples.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SAMPLES_SHA" ]; then
        echo "no-modify: /app/samples.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/classify.py"
OUT = "/tmp/basalt_ember_verify_out.json"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize an answer: exact integer labels, probs rounded to 6 decimals."""
    try:
        assert isinstance(obj, dict), "answer is not a dict"
        assert set(obj.keys()) == {"labels", "probs"}, sorted(obj.keys())
        labels = obj["labels"]
        probs = obj["probs"]
        assert isinstance(labels, list) and isinstance(probs, list)
        assert len(labels) == len(probs)
        lab = [int(v) for v in labels]
        pr = [[round(float(v), 6) for v in row] for row in probs]
        return lab, pr
    except Exception as e:
        raise AssertionError("malformed answer: %r" % (e,))


def run_case(net, samples, expected_path):
    if os.path.exists(OUT):
        os.remove(OUT)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, net, samples, OUT],
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0:
            return False
        with open(OUT) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/classify.py")
else:
    # visible case: EXECUTE the deliverable on the live supplied fixtures
    if not (os.path.isfile("/app/network.json") and os.path.isfile("/app/samples.json")):
        failures.append("visible fixtures missing")
    elif not run_case("/app/network.json", "/app/samples.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # visible-case deliverable: /app/predictions.json must match the visible expected
    if os.path.isfile("/app/predictions.json"):
        try:
            with open("/app/predictions.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("predictions.json does not match visible expected")
        except Exception:
            failures.append("predictions.json unreadable")
    else:
        failures.append("missing /app/predictions.json")

    # hidden cases: genuinely distinct networks/samples with their own expecteds
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            net = os.path.join(base, "network.json")
            samples = os.path.join(base, "samples.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (net, samples, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(net, samples, exp):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden case directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
