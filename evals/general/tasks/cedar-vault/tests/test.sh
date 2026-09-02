#!/bin/bash
# Verifier for cedar-vault: checks the visible deliverables, ENFORCES the
# no-modify rule on /app/model, and EXECUTES /app/generate.py on the visible
# model and on every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_LEXICON_SHA="82ca336caca20c1bcedb146a89779c8a25de9fdd47c72cb3e6cbd35daf1ff731"

no_modify_broken=0
if [ ! -f /app/model/lexicon.json ]; then
    echo "no-modify: /app/model/lexicon.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/model/lexicon.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_LEXICON_SHA" ]; then
        echo "no-modify: /app/model/lexicon.json was modified" >&2
        no_modify_broken=1
    fi
fi
export NO_MODIFY_BROKEN=$no_modify_broken

python3 - <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/generate.py"
failures = []
if os.environ.get("NO_MODIFY_BROKEN") == "1":
    failures.append("visible model modified or missing (no-modify rule)")


def norm(obj):
    """Validate and normalize a generator output object."""
    assert isinstance(obj, dict), "output is not a dict"
    assert set(obj.keys()) == {"prompt", "max_new", "continuation", "full"}, sorted(obj.keys())
    prompt = obj["prompt"]
    assert isinstance(prompt, list) and all(isinstance(t, int) for t in prompt), prompt
    mn = obj["max_new"]
    assert isinstance(mn, int) and mn >= 0, mn
    cont = obj["continuation"]
    assert isinstance(cont, list) and all(isinstance(t, int) for t in cont), cont
    assert len(cont) == mn, ("continuation length %d != max_new %d" % (len(cont), mn))
    full = obj["full"]
    assert isinstance(full, list) and all(isinstance(t, int) for t in full), full
    assert full == prompt + cont, "full != prompt + continuation"
    return {"prompt": prompt, "max_new": mn, "continuation": cont, "full": full}


def run_case(model, prompt_arg, expected_path):
    out = "/tmp/cedar_vault_out.json"
    if os.path.exists(out):
        os.remove(out)
    cmd = [sys.executable, SOLVE, "--model", model, "--out", out]
    if prompt_arg is not None:
        cmd += ["--prompt", prompt_arg]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as e:
        failures.append("run failed for %s: %r" % (model, e))
        return
    if r.returncode != 0 or not os.path.exists(out):
        failures.append("generator exited %d for %s" % (r.returncode, model))
        return
    try:
        with open(out) as f:
            got = norm(json.load(f))
        with open(expected_path) as f:
            want = norm(json.load(f))
        if got != want:
            failures.append("output mismatch for %s" % model)
    except Exception as e:
        failures.append("bad output for %s: %r" % (model, e))


if not os.path.isfile(SOLVE):
    failures.append("missing /app/generate.py")
else:
    # visible case: EXECUTE the deliverable on the shipped model (default prompt)
    if os.path.isfile("/app/model/lexicon.json"):
        run_case("/app/model/lexicon.json", None, "/tests/expected.json")
        # visible-case deliverable: /app/greedy.json must match too
        try:
            with open("/app/greedy.json") as f:
                got = norm(json.load(f))
            with open("/tests/expected.json") as f:
                want = norm(json.load(f))
            if got != want:
                failures.append("/app/greedy.json does not match visible expected")
        except Exception as e:
            failures.append("/app/greedy.json unreadable: %r" % e)
    else:
        failures.append("visible model missing")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            model = os.path.join(base, "model.json")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(model) and os.path.isfile(exp)):
                failures.append("hidden case '%s' malformed" % c)
                continue
            ptxt = os.path.join(base, "prompt.txt")
            parg = None
            if os.path.isfile(ptxt):
                parg = open(ptxt).read().strip()
            run_case(model, parg, exp)
    else:
        failures.append("no hidden cases dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
