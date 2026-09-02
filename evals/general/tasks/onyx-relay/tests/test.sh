#!/bin/bash
# Verifier for onyx-relay: enforces the source-size byte cap and clean compile
# of /app/engine.py, EXECUTES the engine on the visible fixtures and on every
# hidden fixture set in /tests/hidden, and checks /app/preds.csv. Writes
# REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, subprocess, sys

ENGINE = "/app/engine.py"
BYTE_CAP = 5000
LOGIT_TOL = 0.02
failures = []


def check_preds(csv_path, expected_path, label):
    """Compare a predictions CSV against expected.json."""
    try:
        with open(expected_path) as f:
            want = json.load(f)
    except Exception as e:
        failures.append("%s: unreadable expected (%s)" % (label, e))
        return
    try:
        with open(csv_path) as f:
            lines = [ln for ln in f.read().splitlines() if ln.strip()]
    except Exception:
        failures.append("%s: missing/unreadable predictions" % label)
        return
    if not lines or lines[0].strip() != "sid,token,logit":
        failures.append("%s: bad header" % label)
        return
    rows = lines[1:]
    if len(rows) != len(want):
        failures.append("%s: expected %d rows, got %d" % (label, len(want), len(rows)))
        return
    for row, w in zip(rows, want):
        parts = row.split(",")
        if len(parts) != 3:
            failures.append("%s: malformed row %r" % (label, row))
            return
        sid, tok, lg = parts[0], parts[1], parts[2]
        if sid != w["sid"]:
            failures.append("%s: sid order mismatch (%r != %r)" % (label, sid, w["sid"]))
            return
        try:
            tok_i, lg_f = int(tok), float(lg)
        except Exception:
            failures.append("%s: non-numeric row %r" % (label, row))
            return
        if tok_i != int(w["token"]):
            failures.append("%s: %s token %d != expected %d" % (label, sid, tok_i, w["token"]))
            return
        if abs(lg_f - float(w["logit"])) > LOGIT_TOL:
            failures.append("%s: %s logit %.6f too far from %.6f" % (label, sid, lg_f, w["logit"]))
            return


# 1. Deliverable present, within the byte cap, and compiles cleanly.
if not os.path.isfile(ENGINE):
    failures.append("missing /app/engine.py")
else:
    size = os.path.getsize(ENGINE)
    if size > BYTE_CAP:
        failures.append("engine.py is %d bytes > %d byte cap" % (size, BYTE_CAP))
    r = subprocess.run([sys.executable, "-m", "py_compile", ENGINE],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        failures.append("engine.py failed py_compile")

    # 2. Visible fixtures: run the engine fresh.
    out_csv = "/tmp/onyx_relay_visible.csv"
    if os.path.exists(out_csv):
        os.remove(out_csv)
    r = subprocess.run(
        [sys.executable, ENGINE, "/app/fixtures/config.json", "/app/fixtures/state.json",
         "/app/fixtures/data.json", "--out", out_csv],
        capture_output=True, text=True, timeout=240)
    if r.returncode != 0 or not os.path.exists(out_csv):
        failures.append("engine.py failed on visible fixtures (rc=%d)" % r.returncode)
    else:
        check_preds(out_csv, "/tests/expected.json", "visible")

    # 3. /app/preds.csv must exist and match the visible expected values.
    if os.path.isfile("/app/preds.csv"):
        check_preds("/app/preds.csv", "/tests/expected.json", "preds.csv")
    else:
        failures.append("missing /app/preds.csv")

    # 4. Hidden fixture sets with different hyperparameters.
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(os.listdir(hidden))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden, c)
            need = [os.path.join(base, n) for n in ("config.json", "state.json", "data.json", "expected.json")]
            if not all(os.path.isfile(p) for p in need):
                failures.append("hidden '%s' malformed" % c)
                continue
            out_csv = "/tmp/onyx_relay_%s.csv" % c
            if os.path.exists(out_csv):
                os.remove(out_csv)
            r = subprocess.run(
                [sys.executable, ENGINE, need[0], need[1], need[2], "--out", out_csv],
                capture_output=True, text=True, timeout=240)
            if r.returncode != 0 or not os.path.exists(out_csv):
                failures.append("hidden '%s': engine failed (rc=%d)" % (c, r.returncode))
            else:
                check_preds(out_csv, need[3], "hidden/%s" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
