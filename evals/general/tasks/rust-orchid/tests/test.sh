#!/bin/bash
# Verifier for rust-orchid: EXECUTES the deliverable CLI
# (/app/generate_cases.py) on the visible fixture and on hidden TSL specs
# with hidden params.json variants, and compares the frame documents against
# an independent recompute (gen_probe.py) plus deep invariant checks. Also
# checks byte determinism across runs, /app/frames.json correctness, and the
# documented exit codes on malformed inputs. Writes reward to
# /logs/verifier/reward.txt on every path.
set -u
mkdir -p /logs/verifier
TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""
overall=1
finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then printf 1 > /logs/verifier/reward.txt; else printf 0 > /logs/verifier/reward.txt; fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt
log() { echo "rust-orchid verify: $*" >&2; }

python3 - <<'PY'
import json
import os
import shutil
import subprocess
import sys

DELIV = "/app/generate_cases.py"
FRAMES = "/app/frames.json"
PROBE = "/tests/hidden/gen_probe.py"
VIS_SPEC = "/app/specs/printer.tsl"
VIS_PARAMS = "/app/params.json"
BASE = "/tests/hidden"

failures = []


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)
    except Exception as exc:
        failures.append("running %r raised %s" % (cmd, exc))
        return None


def probe_recompute(spec, params):
    r = run(["python3", PROBE, spec, params])
    if r is None or r.returncode != 0:
        failures.append("probe recompute failed for %s: rc=%s %s"
                        % (spec, getattr(r, "returncode", "?"),
                           (r.stderr if r else "")[:200]))
        return None
    try:
        return json.loads(r.stdout)
    except Exception as exc:
        failures.append("probe output unparseable for %s: %s" % (spec, exc))
        return None


def probe_verify(spec, params, agent_path, label):
    r = run(["python3", PROBE, "--verify", spec, params, agent_path])
    if r is None:
        return
    if r.returncode != 0:
        failures.append("%s: %s" % (label, (r.stdout or r.stderr).strip()[:400]))


def generate_out(spec, params, out_path):
    """Run the deliverable; returns (ok, bytes)."""
    if not (os.path.isfile(DELIV) and os.access(DELIV, os.R_OK)):
        failures.append("deliverable %s missing/unreadable" % DELIV)
        return False, b""
    if os.path.exists(out_path):
        os.remove(out_path)
    r = run(["python3", DELIV, spec, params, out_path])
    if r is None:
        return False, b""
    if r.returncode != 0:
        failures.append("deliverable exited %d on %s: %s"
                        % (r.returncode, spec, (r.stderr or "")[:200]))
        return False, b""
    if not os.path.isfile(out_path):
        failures.append("deliverable did not write %s for %s" % (out_path, spec))
        return False, b""
    try:
        with open(out_path, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        failures.append("cannot read output %s: %s" % (out_path, exc))
        return False, b""
    try:
        json.loads(data)
    except Exception as exc:
        failures.append("deliverable output not JSON for %s: %s" % (spec, exc))
        return False, b""
    return True, data


# --- 1. visible spec: deliverable run, byte determinism, frames.json check
ok1, b1 = generate_out(VIS_SPEC, VIS_PARAMS, "/tmp/qz_vis1.json")
ok2, b2 = generate_out(VIS_SPEC, VIS_PARAMS, "/tmp/qz_vis2.json")
if ok1 and ok2:
    if b1 != b2:
        failures.append("deliverable is not byte-deterministic on the visible case")
    if not (os.path.isfile(FRAMES) and os.access(FRAMES, os.R_OK)):
        failures.append("deliverable %s missing" % FRAMES)
    else:
        try:
            with open(FRAMES) as fh:
                delivered = json.load(fh)
            if delivered != json.loads(b1):
                failures.append("/app/frames.json does not match the deliverable's visible run")
        except Exception as exc:
            failures.append("/app/frames.json unreadable/malformed: %s" % exc)
        probe_verify(VIS_SPEC, VIS_PARAMS, FRAMES, "visible frames.json vs recompute")
else:
    failures.append("visible deliverable run failed")

# --- 2. hidden spec/params matrix through the deliverable + recompute
cases = [
    ("conflict_first", os.path.join(BASE, "specs/conflict.tsl"),
     os.path.join(BASE, "params/conflict_first.json")),
    ("conflict_default", os.path.join(BASE, "specs/conflict.tsl"),
     os.path.join(BASE, "params/conflict_default.json")),
    ("conflict_limit3", os.path.join(BASE, "specs/conflict.tsl"),
     os.path.join(BASE, "params/conflict_limit3.json")),
    ("allsingle", os.path.join(BASE, "specs/allsingle.tsl"),
     os.path.join(BASE, "params/allsingle.json")),
    ("unsat", os.path.join(BASE, "specs/unsat.tsl"),
     os.path.join(BASE, "params/unsat.json")),
]
for label, spec, params in cases:
    if not (os.path.isfile(spec) and os.path.isfile(params)):
        failures.append("missing hidden fixture for %s" % label)
        continue
    ok, _ = generate_out(spec, params, "/tmp/qz_hidden_%s.json" % label)
    if not ok:
        continue
    # recompute expectations independently, then deep-verify the agent output
    expected = probe_recompute(spec, params)
    if expected is None:
        continue
    try:
        with open("/tmp/qz_hidden_%s.json" % label) as fh:
            agent = json.load(fh)
        if agent != expected:
            failures.append("hidden '%s': agent output differs from independent recompute" % label)
        else:
            probe_verify(spec, params, "/tmp/qz_hidden_%s.json" % label,
                         "hidden '%s' deep checks" % label)
    except Exception as exc:
        failures.append("hidden '%s': %s" % (label, exc))

# --- 3. robustness: malformed spec / invalid params must exit 1/2 and not
#         write the output file
for label, spec, params, want_rc in [
    ("spec_twodefaults", os.path.join(BASE, "bad/spec_twodefaults.tsl"), VIS_PARAMS, 1),
    ("spec_unknown", os.path.join(BASE, "bad/spec_unknown.tsl"), VIS_PARAMS, 1),
    ("params_strategy", VIS_SPEC, os.path.join(BASE, "bad/params_strategy.json"), 2),
    ("params_negative", VIS_SPEC, os.path.join(BASE, "bad/params_negative.json"), 2),
]:
    out = "/tmp/qz_badout_%s.json" % label
    if os.path.exists(out):
        os.remove(out)
    r = run(["python3", DELIV, spec, params, out])
    if r is None:
        continue
    if r.returncode != want_rc:
        failures.append("robustness '%s': expected exit %d, got %d"
                        % (label, want_rc, r.returncode))
    if os.path.exists(out):
        failures.append("robustness '%s': output file was written on error" % label)

# --- 4. absent-input guard: missing spec file must exit 1
r = run(["python3", DELIV, "/tmp/qz_no_such.tsl", VIS_PARAMS, "/tmp/qz_none.json"])
if r is not None and r.returncode != 1:
    failures.append("missing spec file should exit 1, got %d" % r.returncode)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then overall=1; else overall=0; fi
finalize_reward
exit 0