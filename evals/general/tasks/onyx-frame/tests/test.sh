#!/bin/bash
# Verifier for onyx-frame (executes-deliverable).
#
# Visible: executes /app/splash.py on the shipped /app/spec.json, checks the
#          frame byte-for-byte, the gzip/raw size caps on the source, the
#          no-embedded-pixel rules, the report consistency, the produced
#          /app/splash.txt and /app/frame-report.json, and that /app/spec.json
#          was not modified.
# Hidden : re-runs the deliverable on three genuinely different render specs
#          (wide, tall, thin frames, different ramps/coefficients) with the
#          same checks on fresh expected frames.
#
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped visible spec (agents are told not to modify it).
PRISTINE_SPEC_SHA="$(sha256sum /app/spec.json 2>/dev/null | awk '{print $1}')"
EXPECTED_SPEC_SHA="8e931ddf2830154f4f11294f0483238fa2414885d2f5daf26285ad1a16d95038"

SOLVE="/app/splash.py"
OUT="/tmp/onyx_frame_out.txt"
REP="/tmp/onyx_frame_report.json"

python3 - "$SOLVE" "$OUT" "$REP" "$PRISTINE_SPEC_SHA" "$EXPECTED_SPEC_SHA" <<'PY'
import gzip, json, os, subprocess, sys

SOLVE, OUT, REP = sys.argv[1], sys.argv[2], sys.argv[3]
pristine_sha, expected_sha = sys.argv[4], sys.argv[5]
failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg)


def render_ok(spec, out_path, expected_path, report_path=None):
    """Execute the deliverable on one spec and verify every contract clause."""
    for p in (out_path, REP):
        if os.path.exists(p):
            os.remove(p)
    args = [sys.executable, SOLVE, spec, out_path]
    if report_path:
        args.append(report_path)
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=120)
    except Exception as e:
        fail("execute %s: %s" % (spec, e))
        return False
    if r.returncode != 0:
        fail("renderer exited %d on %s: %s" % (r.returncode, spec, r.stderr[-300:]))
        return False

    # ---- frame bytes
    try:
        with open(spec) as fh:
            sp = json.load(fh)
    except Exception as e:
        fail("unreadable spec %s: %s" % (spec, e))
        return False
    try:
        with open(expected_path) as fh:
            want = fh.read()
    except Exception as e:
        fail("unreadable expected %s: %s" % (expected_path, e))
        return False
    try:
        with open(out_path) as fh:
            got = fh.read()
    except Exception as e:
        fail("missing/unreadable frame output for %s: %s" % (spec, e))
        return False
    if got != want:
        fail("frame mismatch on %s" % spec)
        return False

    # ---- size caps on the renderer source itself
    try:
        with open(SOLVE, "rb") as fh:
            src = fh.read()
    except Exception as e:
        fail("unreadable source: %s" % e)
        return False
    text = src.decode("utf-8", errors="replace")
    raw = len(src)
    try:
        gz = len(gzip.compress(src))
    except Exception as e:
        fail("gzip check failed: %s" % e)
        return False
    if raw > sp["raw_max"]:
        fail("raw size %d exceeds cap %d" % (raw, sp["raw_max"]))
    if gz > sp["gzip_max"]:
        fail("gzip size %d exceeds cap %d" % (gz, sp["gzip_max"]))

    # ---- anti-embedding: no frame row / 16-char pixel run inside the source
    rows = want.split("\n")
    for row in rows:
        if len(row) == sp["width"] and row in text:
            fail("full output row found embedded in source")
            break
    for row in rows:
        for i in range(len(row) - 15):
            if row[i:i + 16] and row[i:i + 16] in text:
                fail("16+ char pixel run from output found embedded in source")
                row = None
                break
        if row is None:
            break

    # ---- report consistency
    rp = report_path or REP
    try:
        with open(rp) as fh:
            rep = json.load(fh)
        assert isinstance(rep, dict), "report not a dict"
        assert set(rep.keys()) == {"raw_bytes", "gzip_bytes", "gzip_max",
                                   "raw_max", "width", "height"}, rep.keys()
        assert rep["raw_bytes"] == raw, (rep["raw_bytes"], raw)
        assert rep["gzip_bytes"] == gz, (rep["gzip_bytes"], gz)
        assert rep["gzip_max"] == sp["gzip_max"], rep
        assert rep["raw_max"] == sp["raw_max"], rep
        assert rep["width"] == sp["width"] and rep["height"] == sp["height"], rep
    except AssertionError as e:
        fail("report mismatch on %s: %s" % (rp, e))
    except Exception as e:
        fail("unreadable/invalid report %s: %s" % (rp, e))
    return not failures


# ---------------- visible case ----------------
if not os.path.isfile("/app/spec.json"):
    fail("/app/spec.json missing")
elif pristine_sha != expected_sha:
    fail("/app/spec.json was modified")

if not os.path.isfile(SOLVE):
    fail("missing /app/splash.py")
else:
    render_ok("/app/spec.json", OUT, "/tests/expected_frame.txt", "/tmp/onyx_frame_vis_report.json")

    # visible-case deliverables produced by the agent must exist and match
    try:
        with open("/app/splash.txt") as fh:
            if fh.read() != open("/tests/expected_frame.txt").read():
                fail("/app/splash.txt does not match visible expected frame")
    except Exception as e:
        fail("missing/unreadable /app/splash.txt: %s" % e)
    try:
        rep = json.load(open("/app/frame-report.json"))
        src = open(SOLVE, "rb").read()
        assert rep["raw_bytes"] == len(src), rep
        assert rep["gzip_bytes"] == len(gzip.compress(src)), rep
        assert rep["gzip_max"] == 400 and rep["raw_max"] == 750, rep
        assert rep["width"] == 56 and rep["height"] == 24, rep
    except AssertionError as e:
        fail("/app/frame-report.json inconsistent: %s" % e)
    except Exception as e:
        fail("missing/unreadable /app/frame-report.json: %s" % e)

    # ---------------- hidden cases ----------------
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        fail("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        spec = os.path.join(base, "spec.json")
        exp = os.path.join(base, "expected_frame.txt")
        if not (os.path.isfile(spec) and os.path.isfile(exp)):
            fail("hidden case '%s' malformed" % c)
            continue
        before = len(failures)
        render_ok(spec, OUT, exp, "/tmp/onyx_frame_%s_report.json" % c)
        if len(failures) > before:
            failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
