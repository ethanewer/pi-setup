#!/bin/bash
# Verifier for silk-meridian: checks the visible deliverables and EXECUTES the
# deliverable program (/app/solve.py) on every hidden case under /tests/hidden
# (stale cache, fresh cache, no cache, revision mismatch). Writes 0/1 to
# /logs/verifier/reward.txt. Never crashes on malformed/missing agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped visible fixtures (the instruction forbids
# modifying them; tampering would defeat the visible-case check).
no_modify_broken=0
for f in model/model.py model/weights.npz manifest.json docs.json query.txt cache/doc_vectors.npz; do
    if [ ! -f "/app/$f" ]; then
        echo "no-modify: /app/$f missing" >&2
        no_modify_broken=1
    fi
done
if [ "$no_modify_broken" = "0" ]; then
    for f in model/model.py manifest.json docs.json query.txt; do
        want="$(cat "/tests/expected_visible/$(echo "$f" | tr '/' '_').sha" 2>/dev/null)"
        got="$(sha256sum "/app/$f" | awk '{print $1}')"
        if [ "$got" != "$want" ]; then
            echo "no-modify: /app/$f was modified" >&2
            no_modify_broken=1
        fi
    done
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("shipped files modified or missing (no-modify rule)")


def run(manifest, docs, query, out_json):
    if os.path.exists(out_json):
        os.remove(out_json)
    try:
        return subprocess.run([sys.executable, SOLVE, manifest, docs, query, out_json],
                              capture_output=True, text=True, timeout=120)
    except Exception as e:
        print("run error:", e)
        return None


def check_response(path, manifest, expected):
    """Returns None if the response matches, else a reason string."""
    try:
        with open(path) as fh:
            got = json.load(fh)
    except Exception as e:
        return "unreadable output (%s)" % e
    if not isinstance(got, dict):
        return "output is not an object"
    keys = {"revision", "ranking", "selected", "scores"}
    if set(got) != keys:
        return "keys %s != %s" % (sorted(got), sorted(keys))
    try:
        with open(manifest) as fh:
            pin = json.load(fh)["revision"]
    except Exception as e:
        return "manifest unreadable (%s)" % e
    if got["revision"] != pin:
        return "revision %r != pinned %r" % (got["revision"], pin)
    if got["ranking"] != expected["ranking"]:
        return "ranking differs"
    if got["selected"] != expected["selected"]:
        return "selected %r != %r" % (got["selected"], expected["selected"])
    sc = got["scores"]
    if not isinstance(sc, dict) or set(sc) != set(expected["ranking"]):
        return "scores keys wrong"
    for i, v in sc.items():
        if not isinstance(v, (int, float)):
            return "score for %s not numeric" % i
    return None


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # ---- visible case: execute the deliverable ------------------------------
    r = run("/app/manifest.json", "/app/docs.json", "/app/query.txt",
            "/tmp/sm_vis.json")
    if r is None or r.returncode != 0:
        failures.append("visible run failed (rc=%s)" % (getattr(r, "returncode", None)))
    else:
        with open("/tests/expected.json") as fh:
            exp = json.load(fh)
        err = check_response("/tmp/sm_vis.json", "/app/manifest.json", exp)
        if err:
            failures.append("visible: " + err)
    # ---- visible-case answer.json deliverable -------------------------------
    if os.path.isfile("/app/answer.json"):
        with open("/tests/expected.json") as fh:
            exp = json.load(fh)
        err = check_response("/app/answer.json", "/app/manifest.json", exp)
        if err:
            failures.append("answer.json: " + err)
    else:
        failures.append("missing /app/answer.json")

    # ---- hidden cases --------------------------------------------------------
    hidden = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden)
                   if os.path.isdir(os.path.join(hidden, d))) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden, c)
        need = ["manifest.json", "docs.json", "query.txt", "expected.json"]
        if not all(os.path.isfile(os.path.join(base, f)) for f in need):
            failures.append("hidden '%s' malformed" % c)
            continue
        with open(os.path.join(base, "expected.json")) as fh:
            exp = json.load(fh)
        out_json = "/tmp/sm_h_%s.json" % c
        r = run(os.path.join(base, "manifest.json"),
                os.path.join(base, "docs.json"),
                os.path.join(base, "query.txt"), out_json)
        if exp.get("expect_failure"):
            # revision-mismatch probe: must exit nonzero and write no output
            if r is not None and r.returncode == 0:
                failures.append("hidden '%s': expected nonzero exit" % c)
            elif r is not None and os.path.exists(out_json):
                failures.append("hidden '%s': wrote output despite mismatch" % c)
            continue
        if r is None or r.returncode != 0:
            failures.append("hidden '%s': run failed (rc=%s)"
                            % (c, getattr(r, "returncode", None)))
            continue
        err = check_response(out_json, os.path.join(base, "manifest.json"), exp)
        if err:
            failures.append("hidden '%s': %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
