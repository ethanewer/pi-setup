#!/bin/bash
# Verifier for myrtle-canyon: checks the reference model is byte-identical to
# the pristine fixture, that MuJoCo 3.2.4 (fresh offline install) imports,
# and EXECUTES the deliverable /app/tuned-model.xml under the acceptance
# simulation on the visible drive and on every hidden drive set, plus the
# plugin-free/self-contained checks and the MUJOCO_OK report. Writes reward
# to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, re, sys

failures = []

REF = "/app/ref-model.xml"
TUNED = "/app/tuned-model.xml"
REPORT = "/app/sim-report.txt"
PRISTINE = "/opt/pristine/ref-model.xml"

# --- 1. Reference model untouched (byte-for-byte).
try:
    with open(REF, "rb") as fh:
        ref_bytes = fh.read()
    with open(PRISTINE, "rb") as fh:
        pristine_bytes = fh.read()
    if ref_bytes != pristine_bytes:
        failures.append("reference model was modified")
except OSError as exc:
    failures.append("cannot read reference model: %s" % exc)
    ref_bytes = None

# --- 2. Fresh MuJoCo installation available (agent-installed, pinned).
mujoco = None
try:
    import mujoco as _mj
    if _mj.__version__ != "3.2.4":
        failures.append("mujoco version %s installed, expected 3.2.4" % _mj.__version__)
    mujoco = _mj
except Exception as exc:
    failures.append("mujoco import failed: %s" % exc)

def sweep(path, ctrl, secs=2.0):
    m = mujoco.MjModel.from_xml_path(path)
    d = mujoco.MjData(m)
    d.ctrl[0] = ctrl
    mx = 0.0
    for _ in range(round(secs / m.opt.timestep)):
        mujoco.mj_step(m, d)
        mx = max(mx, abs(d.qpos[0]))
    return mx, m.nplugin

# --- 3. Tuned model exists, differs, self-contained, plugin-free.
tuned_ok = False
if os.path.isfile(TUNED):
    try:
        with open(TUNED, "rb") as fh:
            tuned_bytes = fh.read()
        if ref_bytes is not None and tuned_bytes == ref_bytes:
            failures.append("tuned model is byte-identical to the reference")
        text = tuned_bytes.decode("utf-8", errors="replace")
        lowered = text.lower()
        for bad in ("<plugin", "<include", "<asset", "meshdir", "texturedir"):
            if bad in lowered:
                failures.append("tuned model is not self-contained (%s found)" % bad)
    except OSError as exc:
        failures.append("tuned model unreadable: %s" % exc)
    if mujoco is not None:
        try:
            mx, npl = sweep(TUNED, 2.0)
            if npl != 0:
                failures.append("tuned model loads with %d plugin(s)" % npl)
            if not (mx > 0.35):
                failures.append("tuned model visible-drive sweep %.4f below 0.35" % mx)
            else:
                tuned_ok = True
            # tuned model must keep exactly one slide joint + one motor
            m = mujoco.MjModel.from_xml_path(TUNED)
            if m.nq != 1 or m.nu != 1:
                failures.append("tuned model must have exactly one joint and one actuator")
        except Exception as exc:
            failures.append("tuned model failed to load/simulate: %s" % exc)
else:
    failures.append("missing /app/tuned-model.xml")

# --- 4. Reference stays below threshold under the same drives.
if mujoco is not None and ref_bytes is not None:
    for ctrl, label in ((2.0, "visible"), (-2.5, "hidden-neg")):
        try:
            mx, _ = sweep(REF, ctrl)
            if not (mx < 0.10):
                failures.append("reference sweep %.4f not below 0.10 (%s drive)" % (mx, label))
        except Exception as exc:
            failures.append("reference simulation failed: %s" % exc)

# --- 5. Hidden drive sets through the deliverable.
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        spec_path = os.path.join(hidden_dir, case, "drives.json")
        if not os.path.isfile(spec_path):
            failures.append("hidden '%s' malformed" % case)
            continue
        try:
            with open(spec_path) as fh:
                spec = json.load(fh)
            drives = spec["drives"]
            min_sweep = float(spec.get("min_sweep", 0.35))
            max_ref = float(spec.get("max_ref", 0.10))
        except Exception:
            failures.append("hidden '%s' drives.json unreadable" % case)
            continue
        if not isinstance(drives, list) or not drives:
            failures.append("hidden '%s' has no drives" % case)
            continue
        if mujoco is None or not tuned_ok:
            failures.append("hidden '%s' skipped (no tuned model / no mujoco)" % case)
            continue
        for ctrl in drives:
            if not isinstance(ctrl, (int, float)):
                failures.append("hidden '%s' bad drive" % case)
                continue
            try:
                t_mx, _ = sweep(TUNED, ctrl)
                r_mx, _ = sweep(REF, ctrl)
                if not (t_mx > min_sweep):
                    failures.append("hidden '%s' drive %s tuned sweep %.4f <= %.2f"
                                    % (case, ctrl, t_mx, min_sweep))
                if not (r_mx < max_ref):
                    failures.append("hidden '%s' drive %s ref sweep %.4f >= %.2f"
                                    % (case, ctrl, r_mx, max_ref))
            except Exception as exc:
                failures.append("hidden '%s' drive %s simulation error: %s"
                                % (case, ctrl, exc))
else:
    failures.append("no hidden cases directory")

# --- 6. MUJOCO_OK report deliverable.
try:
    with open(REPORT, "r", encoding="utf-8") as fh:
        first = fh.readline().strip()
    if not first.startswith("MUJOCO_OK"):
        failures.append("sim-report.txt first line does not start with MUJOCO_OK")
except OSError as exc:
    failures.append("sim-report.txt unreadable: %s" % exc)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
