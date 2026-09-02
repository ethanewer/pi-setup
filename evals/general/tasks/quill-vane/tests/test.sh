#!/bin/bash
# Verifier for quill-vane (executes-deliverable): checks the visible-case
# deliverables, ENFORCES the no-modify rule on the shipped images/probe, and
# EXECUTES /app/eval_funcs.py on the visible probe and on every hidden probe in
# /tests/hidden, comparing to ground truth. Writes 0/1 to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

PRISTINE_PROBE_SHA="$(awk '{print $1}' /tests/pristine_probe.sha)"
probe_ok=1
if [ ! -f /app/probe.json ]; then
    echo "no-modify: /app/probe.json missing" >&2
    probe_ok=0
else
    actual="$(sha256sum /app/probe.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PROBE_SHA" ]; then
        echo "no-modify: /app/probe.json was modified" >&2
        probe_ok=0
    fi
fi
for img in /app/snippets/func_a.png /app/snippets/func_b.png /app/snippets/func_c.png; do
    if [ ! -f "$img" ]; then
        echo "no-modify: $img missing" >&2
        probe_ok=0
    fi
done

python3 - "$probe_ok" <<'PY'
import json
import os
import subprocess
import sys

EVAL = "/app/eval_funcs.py"
probe_ok = int(sys.argv[1])
failures = []

if probe_ok != 1:
    failures.append("shipped fixtures missing or modified (no-modify rule)")


def norm(v):
    if isinstance(v, bool):
        return ("bool", v)
    if isinstance(v, int):
        return ("num", float(v))
    if isinstance(v, float):
        return ("num", round(v, 6))
    if isinstance(v, str):
        return ("str", v)
    if isinstance(v, list):
        return ("list", [norm(x) for x in v])
    if isinstance(v, dict):
        return ("dict", {k: norm(v[k]) for k in sorted(v)})
    return ("other", repr(v))


def run_case(probe_path, expected_path, tag):
    out = "/tmp/quill_vane_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, EVAL, "/app/snippets", probe_path, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        failures.append("%s: exec error %r" % (tag, exc))
        return
    if r.returncode != 0:
        failures.append("%s: rc=%d stderr=%r" % (tag, r.returncode, r.stderr[-200:]))
        return
    if not os.path.exists(out):
        failures.append("%s: no output file written" % tag)
        return
    try:
        with open(out) as fh:
            got = json.load(fh)
        with open(expected_path) as fh:
            want = json.load(fh)
    except Exception as exc:
        failures.append("%s: unreadable output/expected: %r" % (tag, exc))
        return
    if not isinstance(got, dict):
        failures.append("%s: output is not a JSON object" % tag)
        return
    if set(got.keys()) != {"func_a", "func_b", "func_c"}:
        failures.append("%s: keys %r != ['func_a','func_b','func_c']"
                        % (tag, sorted(got.keys())))
        return
    if norm(got) != norm(want):
        failures.append("%s: results %r != expected %r" % (tag, got, want))


if not os.path.isfile(EVAL):
    failures.append("missing /app/eval_funcs.py")
else:
    # Visible case: execute the deliverable on the shipped probe.
    run_case("/app/probe.json", "/tests/expected.json", "visible")

    # Visible-case deliverable: /app/answer.json must match the expected.
    try:
        with open("/app/answer.json") as fh:
            got = json.load(fh)
        with open("/tests/expected.json") as fh:
            want = json.load(fh)
        if norm(got) != norm(want):
            failures.append("/app/answer.json does not match visible expected")
    except Exception as exc:
        failures.append("/app/answer.json unreadable: %r" % exc)

    # Hidden probes: the SAME photographed snippets, different arguments.
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden_dir, case)
        probe = os.path.join(base, "probe.json")
        exp = os.path.join(base, "expected.json")
        if not (os.path.isfile(probe) and os.path.isfile(exp)):
            failures.append("hidden case '%s' malformed" % case)
            continue
        run_case(probe, exp, "hidden/%s" % case)

print("verify failures:", failures)
if failures:
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
else:
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("1")
PY
exit 0
