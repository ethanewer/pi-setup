#!/bin/bash
# Verifier for orchid-model: executes the deliverables — the self-test entry on
# the visible weight set and on hidden good/corrupted weight sets, the predict
# CLI on hidden samples, and checks the visible predictions.csv. Writes REWARD
# (0/1) to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import ast, importlib.util, json, os, subprocess, sys

FAIL = []


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------- deliverables present ----------
for p in ("/app/nn.py", "/app/selftest.py", "/app/predict.py", "/app/predictions.csv"):
    if not os.path.isfile(p):
        FAIL.append("missing deliverable %s" % p)
if FAIL:
    print("verify failures:", FAIL)
    with open("/logs/verifier/reward.txt", "w") as f:
        f.write("0")
    sys.exit(0)

# ---------- static check: no broad exception swallowing in selftest.py ----------
try:
    tree = ast.parse(open("/app/selftest.py").read())
except SyntaxError as e:
    FAIL.append("selftest.py does not parse: %s" % e)
    tree = None
if tree is not None:
    for node in ast.walk(tree):
        if isinstance(node, ast.ExceptHandler):
            t = node.type
            if t is None:
                FAIL.append("selftest.py contains a bare except:")
            else:
                names = set()
                if isinstance(t, ast.Name):
                    names.add(t.id)
                elif isinstance(t, ast.Tuple):
                    names |= {e.id for e in t.elts if isinstance(e, ast.Name)}
                for bad in ("BaseException", "Exception"):
                    if bad in names:
                        FAIL.append("selftest.py swallows %s" % bad)

# ---------- self-test entry: visible weight set ----------
r = run([sys.executable, "/app/selftest.py", "/app/weights"])
if r.returncode != 0:
    FAIL.append("selftest visible exit=%d" % r.returncode)
if "SELFTEST_OK" not in r.stdout:
    FAIL.append("selftest visible missing SELFTEST_OK")
if "SELFTEST_FAIL" in r.stdout:
    FAIL.append("selftest visible printed SELFTEST_FAIL")

try:
    st = load_module("/app/selftest.py", "agent_selftest")
    if not hasattr(st, "run_selftest"):
        FAIL.append("selftest.py lacks run_selftest")
    elif st.run_selftest("/app/weights") is not True:
        FAIL.append("run_selftest visible not True")
except Exception as e:
    FAIL.append("selftest.py import/run error: %r" % e)

# ---------- nn.py is a real library ----------
try:
    nnmod = load_module("/app/nn.py", "agent_nn")
    if not (hasattr(nnmod, "forward") and hasattr(nnmod, "load_weights")):
        FAIL.append("nn.py lacks forward/load_weights")
except Exception as e:
    FAIL.append("nn.py import error: %r" % e)

# ---------- self-test entry: hidden weight sets ----------
HID = "/tests/hidden"
GOOD = {"good-net", "good-net-2"}
BAD = {"bad-bias", "bad-w", "bad-keys"}
if os.path.isdir(HID):
    for case in sorted(os.listdir(HID)):
        wdir = os.path.join(HID, case, "weights")
        if not os.path.isdir(wdir) or case not in (GOOD | BAD):
            continue  # other hidden cases (e.g. predict-only) are checked elsewhere
        exp_pass = case in GOOD
        r = run([sys.executable, "/app/selftest.py", wdir])
        passed = (r.returncode == 0 and "SELFTEST_OK" in r.stdout
                  and "SELFTEST_FAIL" not in r.stdout)
        if passed != exp_pass:
            FAIL.append("selftest hidden '%s': passed=%s expected_pass=%s exit=%d"
                        % (case, passed, exp_pass, r.returncode))
        if not exp_pass and "SELFTEST_OK" in r.stdout:
            FAIL.append("selftest hidden '%s' faked success" % case)
        try:
            st2 = load_module("/app/selftest.py", "agent_selftest_h")
            got = st2.run_selftest(wdir)
            if got is not exp_pass:
                FAIL.append("run_selftest hidden '%s' -> %r" % (case, got))
        except Exception as e:
            FAIL.append("run_selftest hidden '%s' raised: %r" % (case, e))

# ---------- visible predictions.csv ----------
def norm_csv(path):
    try:
        return [ln.strip() for ln in open(path) if ln.strip()]
    except Exception:
        return None

got_vis = norm_csv("/app/predictions.csv")
want_vis = norm_csv("/tests/expected_predictions.csv")
if got_vis != want_vis:
    FAIL.append("predictions.csv mismatch")

# ---------- predict.py on hidden case ----------
pa = os.path.join(HID, "predict-alt")
if os.path.isdir(pa):
    out = "/tmp/orchid_pred_out.csv"
    if os.path.exists(out):
        os.remove(out)
    r = run([sys.executable, "/app/predict.py", os.path.join(pa, "weights"),
             os.path.join(pa, "samples.csv"), out])
    if r.returncode != 0:
        FAIL.append("predict hidden exit=%d" % r.returncode)
    elif norm_csv(out) != norm_csv(os.path.join(pa, "expected.csv")):
        FAIL.append("predict hidden output mismatch")

print("verify failures:", FAIL)
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not FAIL else "0")
sys.exit(0)
PY
