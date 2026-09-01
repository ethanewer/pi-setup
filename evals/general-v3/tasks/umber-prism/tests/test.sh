#!/bin/bash
# Verifier for umber-prism: checks the visible-case deliverables, ENFORCES the
# no-modify rule on the supplied /app inputs, and EXECUTES the deliverable
# program (/app/screen.py) on the visible case and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_COMPOUNDS_SHA="4c18863dc94ae77f1a8eea6af5ff5c9bf42591ca4b3f3a804d3ebb60a9933db0"
PRISTINE_MASSES_SHA="4d5a70e7d932be3348a442835a0a811fd7654a92018d02538d39fc61eec3317b"
PRISTINE_SCREEN_SHA="8d580ec5a159be85124d85783e72f91d61b2d7e2a27dadb349a85d454a8970de"

no_modify_broken=0
for pair in "/app/compounds.jsonl:$PRISTINE_COMPOUNDS_SHA" \
            "/app/atomic_masses.json:$PRISTINE_MASSES_SHA" \
            "/app/screen.json:$PRISTINE_SCREEN_SHA"; do
    path="${pair%%:*}"; want="${pair##*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/screen.py"
no_modify_broken = int(sys.argv[1])
failures = []


def r6(x):
    return round(float(x), 6)


def norm_ranked_line(line):
    obj = json.loads(line)
    assert isinstance(obj, dict), obj
    assert set(obj) == {"id", "formula", "molar_mass", "distance", "dnorm",
                        "score"}, sorted(obj)
    return (str(obj["id"]), str(obj["formula"]), r6(obj["molar_mass"]),
            r6(obj["distance"]), r6(obj["dnorm"]), r6(obj["score"]))


def norm_report(obj):
    assert isinstance(obj, dict), obj
    assert set(obj) == {"candidates", "parsed", "kept", "skipped", "target",
                        "tolerance"}, sorted(obj)
    return (int(obj["candidates"]), int(obj["parsed"]), int(obj["kept"]),
            int(obj["skipped"]), r6(obj["target"]), r6(obj["tolerance"]))


def read_ranked(path):
    with open(path, "r", encoding="utf-8") as fh:
        return [norm_ranked_line(l) for l in fh if l.strip()]


def read_report(path):
    with open(path, "r", encoding="utf-8") as fh:
        return norm_report(json.load(fh))


def run_case(compounds, masses, screen, exp_ranked, exp_report):
    out = "/tmp/umber_prism_verify_ranked.jsonl"
    rep = "/tmp/umber_prism_verify_report.json"
    for p in (out, rep):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run(
        [sys.executable, SOLVE, "--compounds", compounds, "--masses", masses,
         "--screen", screen, "--output-jsonl", out, "--report", rep],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        return False
    try:
        got_ranked = read_ranked(out) if os.path.exists(out) else []
        got_report = read_report(rep) if os.path.exists(rep) else None
        want_ranked = read_ranked(exp_ranked)
        want_report = read_report(exp_report)
    except Exception:
        return False
    return got_ranked == want_ranked and got_report == want_report


if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/screen.py")
else:
    # --- visible case: EXECUTE screen.py on the live supplied inputs ---
    vis = ("/app/compounds.jsonl", "/app/atomic_masses.json", "/app/screen.json")
    if not all(os.path.isfile(p) for p in vis):
        failures.append("visible inputs missing")
    elif not run_case(vis[0], vis[1], vis[2],
                      "/tests/expected_ranked.jsonl", "/tests/expected_report.json"):
        failures.append("visible case failed")

    # --- visible deliverables must exist and match the visible expected ---
    try:
        with open("/tests/expected_report.json") as f:
            want_report = norm_report(json.load(f))
    except Exception:
        want_report = None
        failures.append("visible expected report unreadable")
    for path in ("/app/ranked.jsonl", "/app/screen_report.json"):
        if not os.path.isfile(path):
            failures.append("missing %s" % path)
    if want_report is not None and os.path.isfile("/app/screen_report.json"):
        try:
            if read_report("/app/screen_report.json") != want_report:
                failures.append("screen_report.json does not match expected")
        except Exception:
            failures.append("screen_report.json unreadable")
    if os.path.isfile("/app/ranked.jsonl") and os.path.isfile("/tests/expected_ranked.jsonl"):
        try:
            if read_ranked("/app/ranked.jsonl") != read_ranked("/tests/expected_ranked.jsonl"):
                failures.append("ranked.jsonl does not match expected")
        except Exception:
            failures.append("ranked.jsonl unreadable")

    # --- hidden cases: genuinely distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            compounds = os.path.join(base, "compounds.jsonl")
            masses = os.path.join(base, "atomic_masses.json")
            screen = os.path.join(base, "screen.json")
            exp_r = os.path.join(base, "expected.jsonl")
            exp_p = os.path.join(base, "expected_report.json")
            if not all(os.path.isfile(p) for p in
                       (compounds, masses, screen, exp_r, exp_p)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(compounds, masses, screen, exp_r, exp_p):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
