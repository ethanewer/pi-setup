#!/bin/bash
# Verifier for brass-lantern: enforces the no-modify rule on the visible card,
# checks /app/adapter_config.json, and EXECUTES /app/make_adapter.py on every
# hidden card (with hidden flag combinations). Writes 0/1 to reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of /app/model_card.json as shipped:
PRISTINE="323eaf1e14317f90acc6bc8a7c4821593581e7cc3cc6b5b4f8b6f92e6b3ac705"

if [ ! -f /app/model_card.json ]; then
    echo "no-modify: /app/model_card.json missing" >&2
    broken=1
else
    actual="$(sha256sum /app/model_card.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE" ]; then
        echo "no-modify: model_card.json was modified" >&2
        broken=1
    else
        broken=0
    fi
fi

python3 - "$broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/make_adapter.py"
broken = int(sys.argv[1])
failures = []

if broken:
    failures.append("visible card modified or missing")


def run_case(card, out, extra_args, expected_path):
    if os.path.exists(out):
        os.remove(out)
    cmd = [sys.executable, SOLVE, card, out] + list(extra_args)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except Exception as e:
        return "execution error: %r" % (e,)
    if r.returncode != 0 or not os.path.exists(out):
        return "exit %d without output" % r.returncode
    try:
        got = json.load(open(out))
        want = json.load(open(expected_path))
    except Exception as e:
        return "unreadable output: %r" % (e,)
    if got != want:
        return "config mismatch: got %r want %r" % (got, want)
    return None


if not os.path.isfile(SOLVE):
    failures.append("missing /app/make_adapter.py")
else:
    if not broken:
        err = run_case("/app/model_card.json", "/tmp/brass_visible.json", [],
                       "/tests/expected.json")
        if err:
            failures.append("visible case: " + err)

    if not os.path.isfile("/app/adapter_config.json"):
        failures.append("missing /app/adapter_config.json")
    else:
        try:
            if json.load(open("/app/adapter_config.json")) != \
               json.load(open("/tests/expected.json")):
                failures.append("/app/adapter_config.json does not match visible expected")
        except Exception as e:
            failures.append("adapter_config.json unreadable: %r" % (e,))

    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden, case)
        try:
            params = json.load(open(os.path.join(base, "params.json")))
        except Exception:
            failures.append("hidden '%s' malformed params" % case)
            continue
        card = os.path.join(base, params.get("card", "card.json"))
        exp = os.path.join(base, "expected.json")
        if not (os.path.isfile(card) and os.path.isfile(exp)):
            failures.append("hidden '%s' malformed fixture" % case)
            continue
        err = run_case(card, "/tmp/brass_out_%s.json" % case,
                       params.get("args", []), exp)
        if err:
            failures.append("hidden '%s': %s" % (case, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
