#!/bin/bash
# Verifier for sable-codon: ENFORCES the no-modify rule on the shipped /app
# inputs, then EXECUTES the deliverable (/app/design.py) on the visible scene
# and on every hidden scene in /tests/hidden, comparing each design JSON to
# its expected.json. Writes REWARD (0/1) to /logs/verifier/reward.txt. Never
# crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

no_modify_broken=0

python3 - "$no_modify_broken" <<'PY'
import hashlib, json, os, subprocess, sys

SOLVE = "/app/design.py"
no_modify_broken = int(sys.argv[1])

failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def norm(path):
    with open(path) as fh:
        obj = json.load(fh)
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {
        "template_id", "locus", "insert", "anneal_bounds", "tm_bounds",
        "gc_bounds", "error", "forward", "reverse",
    }, sorted(obj.keys())
    for k in ("template_id", "insert"):
        assert isinstance(obj[k], str), k
    assert obj["error"] is None or isinstance(obj["error"], str), obj["error"]
    for k in ("locus", "anneal_bounds", "tm_bounds", "gc_bounds"):
        assert isinstance(obj[k], dict), k
    for k in ("forward", "reverse"):
        v = obj[k]
        if v is None:
            continue
        assert set(v.keys()) == {
            "seq", "upstream_len", "downstream_len", "tm", "gc_percent"
        }, v
        assert isinstance(v["seq"], str)
        assert isinstance(v["upstream_len"], int)
        assert isinstance(v["downstream_len"], int)
        assert isinstance(v["tm"], (int, float))
        assert isinstance(v["gc_percent"], (int, float))
        v["tm"] = round(float(v["tm"]), 4)
        v["gc_percent"] = round(float(v["gc_percent"]), 1)
    return obj


def run_case(scene_path, expected_path, tag):
    out = "/tmp/sable_codon_%s.json" % tag
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--scene", scene_path, "--out", out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        return norm(out) == norm(expected_path)
    except Exception:
        return False


# no-modify checks on the shipped visible inputs
for path, want in (
    ("/app/plasmid.fasta",
     "972ee907a1f3a040461e1386fe0205e97f07f52b8db4f8facec0bf6c2f814a6b"),
    ("/app/scene.json",
     "d7f37e278d09ee431b8d87edae15bb83336863c1351d3ec5bc7b0d60cef0254a"),
):
    if not os.path.isfile(path):
        failures.append("missing %s" % path)
    elif sha256(path) != want:
        failures.append("%s was modified (no-modify rule)" % path)

if not os.path.isfile(SOLVE):
    failures.append("missing /app/design.py")
else:
    # scene-file-level failures must exit non-zero (missing scene)
    r = subprocess.run(
        [sys.executable, SOLVE, "--scene", "/nonexistent/scene.json",
         "--out", "/tmp/sable_codon_neg.json"],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode == 0:
        failures.append("design.py did not fail on a missing scene file")

    # visible case
    if not run_case("/app/scene.json", "/tests/expected/visible.json", "visible"):
        failures.append("visible case failed")

    # visible deliverable file
    if os.path.isfile("/app/primers.json"):
        try:
            if norm("/app/primers.json") != norm("/tests/expected/visible.json"):
                failures.append("primers.json does not match visible expected")
        except Exception:
            failures.append("primers.json unreadable")
    else:
        failures.append("missing /app/primers.json")

    # hidden cases
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            scene = os.path.join(base, "scene.json")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(scene) and os.path.isfile(exp)
                    and os.path.isfile(os.path.join(base, "template.fasta"))):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(scene, exp, c):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
