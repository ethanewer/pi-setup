#!/bin/bash
# Verifier for cobalt-beacon: checks the visible-case deliverables, enforces
# the no-modify rule on the supplied /app fixtures, and EXECUTES the
# deliverable program (/app/solve.py) on the visible case and on every hidden
# generator/target fixture in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (agent must not modify them).
PRISTINE_GEN_SHA="299fc50b95335e73a1d3a99ddae5c612337d0bf74af631ccb8a117543d45af8a"
PRISTINE_TGT_SHA="0cfec7417bf2817bd6bfeec191824e3bb4daef2a1a509c3fc56a1e400277f950"

no_modify_broken=0
for pair in "/app/beacon_gen.py:$PRISTINE_GEN_SHA" "/app/beacon.target:$PRISTINE_TGT_SHA"; do
    path="${pair%%:*}"; want="${pair#*:}"
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

export NO_MODIFY_BROKEN="$no_modify_broken"
python3 - <<'PY'
import json, os, shutil, subprocess, sys, tempfile

SOLVE = "/app/solve.py"
failures = []

if os.environ.get("NO_MODIFY_BROKEN") == "1":
    failures.append("visible inputs modified or missing (no-modify rule)")


def norm(obj):
    try:
        assert isinstance(obj, dict), obj
        assert set(obj.keys()) == {"target", "matches", "match_count"}, sorted(obj.keys())
        target = int(obj["target"])
        matches = [str(m) for m in obj["matches"]]
        mc = int(obj["match_count"])
        assert mc == len(matches), (mc, len(matches))
        return (target, sorted(matches), mc)
    except Exception as exc:
        raise AssertionError("bad answer object: %r" % (exc,))


def run_case(gen, tgt, expected_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, gen, tgt, out_path],
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0 or not os.path.exists(out_path):
            return False
        with open(out_path) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied fixtures ---
    if not run_case("/app/beacon_gen.py", "/app/beacon.target",
                    "/tests/expected.json", "/tmp/cobalt_beacon_visible.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must match too ---
    try:
        with open("/app/answer.json") as f:
            got = json.load(f)
        with open("/tests/expected.json") as f:
            want = json.load(f)
        if norm(got) != norm(want):
            failures.append("answer.json does not match visible expected")
    except Exception:
        failures.append("answer.json missing or unreadable")

    # --- hidden cases: fresh generators/targets, run unchanged ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            if not all(os.path.isfile(os.path.join(base, n))
                       for n in ("beacon_gen.py", "beacon.target", "expected.json")):
                failures.append("hidden '%s' malformed" % c)
                continue
            work = tempfile.mkdtemp(prefix="cobalt_hc_")
            try:
                gen = os.path.join(work, "beacon_gen.py")
                tgt = os.path.join(work, "beacon.target")
                shutil.copy(os.path.join(base, "beacon_gen.py"), gen)
                shutil.copy(os.path.join(base, "beacon.target"), tgt)
                if not run_case(gen, tgt, os.path.join(base, "expected.json"),
                                os.path.join(work, "out.json")):
                    failures.append("hidden case '%s' failed" % c)
            finally:
                shutil.rmtree(work, ignore_errors=True)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
