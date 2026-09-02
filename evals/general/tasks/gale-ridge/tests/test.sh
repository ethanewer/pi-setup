#!/usr/bin/env bash
# Gale Ridge verifier. Runs after the agent/oracle, as root. /tests is mounted
# read-only; /logs/verifier is writable. Always ends writing a numeric reward.
set -uo pipefail

mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, pathlib, subprocess, sys, urllib.request

REWARD = "/logs/verifier/reward.txt"
EXPECTED_SHAPES = {
    "instance_encoder.weight": [10, 784],
    "instance_encoder.bias": [10],
    "bag_classifier.weight": [10, 10],
    "bag_classifier.bias": [10],
}
FAILURES = []

def write(v):
    with open(REWARD, "w", encoding="utf-8") as fh:
        fh.write(str(v))


def ok(label, detail=""):
    print(f"  pass: {label}" + (f"  {detail}" if detail else ""))

def fail(label, detail=""):
    FAILURES.append(label)
    print(f"  FAIL: {label}  {detail}")

def run_cli(args, timeout=180):
    return subprocess.run(
        [sys.executable, "/app/workflow.py"] + args,
        capture_output=True, text=True, timeout=timeout,
    )

def load_report(p):
    with open(p, "r", encoding="utf-8") as fh:
        return json.load(fh)

def http_ok(port, path="/health", timeout=3):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False

# ---------------------------------------------------------------- deliverables
wf = pathlib.Path("/app/workflow.py")
art = pathlib.Path("/app/artifact")
if not wf.is_file():
    fail("deliverable /app/workflow.py exists")
    write("0")
    sys.exit(0)
if not art.is_dir():
    fail("deliverable /app/artifact exists")
    write("0")
    sys.exit(0)
ok("/app/workflow.py and /app/artifact present")

# ---------------------------------------------------------------- main report
mrep_path = art / "report.json"
if not mrep_path.is_file():
    fail("main report.json exists")
    write("0")
    sys.exit(0)
mrep = load_report(mrep_path)

def flag(name, val=True):
    if val is True:
        ok(f"main {name}")
    else:
        fail(f"main {name}", f"got {mrep.get(name)}")

flag("offline_load_ok", mrep.get("offline_load_ok") is True)
flag("tokenizer_roundtrip_ok", mrep.get("tokenizer_roundtrip_ok") is True)
flag("shapes_preserved", mrep.get("shapes_preserved") is True)
flag("reload_predicts", mrep.get("reload_predicts") is True)
flag("loads_cap_ok", mrep.get("loads_cap_ok") is True)
flag("init_ok", mrep.get("init_ok") is True)
flag("mlflow_ok", mrep.get("mlflow_ok") is True)
flag("fixed_shapes exact", mrep.get("fixed_shapes") == EXPECTED_SHAPES)
flag("mlflow_port 8080", mrep.get("mlflow_port") == 8080)
flag("head_out default 7", mrep.get("head_out") == 7)
flag("shapes_cap default 3", mrep.get("shapes_cap") == 3)
flag("best_edit is width A", mrep.get("best_edit") == "A")
flag("config_file present", isinstance(mrep.get("config_file"), str))

# init consistency
if mrep.get("init_ok") is True and int(mrep.get("init_min", 0)) > int(mrep.get("init_params", 0)):
    fail("init_ok consistent", f"params {mrep.get('init_params')} < min {mrep.get('init_min')}")
else:
    ok("init_ok consistent with init_params")

# capacity: width letter strictly dominates every lever
caps = mrep.get("capacities") or {}
if best := mrep.get("best_edit"):
    if best != "A":
        fail("best_edit", best)
if not isinstance(caps, dict) or not caps:
    fail("capacities present")
else:
    a = caps.get("A")
    if a is None or not all(a > v for k, v in caps.items() if k != "A"):
        fail("width dominates levers", str(caps))
    else:
        ok("width letter dominates all levers in capacity")

# every documented artifact file
for f in ("BagNet.pt", "seqhead.pt", "reload_pred.json", "shapes_trace.json", "report.json"):
    if (art / f).is_file():
        ok(f"artifact {f}")
    else:
        fail("artifact file present", f)

# shapes_trace distinct set must actually be <= cap
try:
    tr = load_report(art / "shapes_trace.json")
    shapes = tr.get("shapes") or []
    distinct = len({tuple(s) for s in shapes})
    cap = int(mrep.get("shapes_cap"))
    if distinct <= cap:
        ok("trace distinct shapes", f"{distinct} <= {cap}")
    else:
        fail("trace distinct shapes", f"{distinct} > {cap}")
except Exception as e:
    fail("shapes_trace.json readable", str(e))

# ---------------------------------------------------------------- mlflow live
if http_ok(8080):
    ok("mlflow /health serving on 8080")
else:
    fail("mlflow /health on 8080")

# ------------------------------------------------- check-artifact positive
r = run_cli(["--check-artifact", str(art / "BagNet.pt"), "--out", "/tmp/vchk_pos"])
cp = pathlib.Path("/tmp/vchk_pos/check_artifact.json")
try:
    res = load_report(cp)
    if res.get("load_ok") is True:
        ok("--check-artifact real BagNet.pt -> load_ok true")
    else:
        fail("--check-artifact positive", str(res))
except Exception as e:
    fail("--check-artifact positive wrote check_artifact.json", str(e))

# ------------------------------------------------------------ corrupt artifact
cpath = "/tmp/corrupt.pt"
with open(cpath, "w", encoding="utf-8") as fh:
    fh.write("this is definitely not a torch tensor file -- gale ridge garbage\n")
r = run_cli(["--check-artifact", cpath, "--out", "/tmp/vcneg"])
try:
    res = load_report("/tmp/vcneg/check_artifact.json")
    if res.get("load_ok") is False:
        ok("--check-artifact corrupt -> load_ok false")
    else:
        fail("--check-artifact negative", str(res))
except Exception as e:
    fail("--check-artifact negative output", str(e))
# corrupt load must exit 0 in both cases
if r.returncode != 0:
    fail("--check-artifact corrupt exit 0", f"rc={r.returncode}")

# ---------------------------------------------------------------- hidden cases
def hidden_run(config_rel, outdir, expectations):
    cfg = f"/tests/hidden/{config_rel}"
    out = f"/tmp/{outdir}"
    pre = subprocess.run([sys.executable, "/app/workflow.py", "--config", cfg, "--out", out], capture_output=True, text=True, timeout=240)
    if pre.returncode != 0:
        fail(f"hidden {config_rel} exit 0", f"rc={pre.returncode}: {pre.stderr[-400:]}")
        return
    try:
        rep = load_report(os.path.join(out, "report.json"))
    except Exception as e:
        fail(f"hidden {config_rel} report.json", str(e))
        return
    for name, pred in expectations.items():
        if pred(rep):
            ok(f"hidden {config_rel} {name}")
        else:
            fail(f"hidden {config_rel} {name}", f"report got {rep.get(name)}")

# cap1: at most one distinct shape
hidden_run("cap1.json", "hc1", {
    "loads_cap_ok": lambda r: r.get("loads_cap_ok") is True,
    "shapes_cap==1": lambda r: r.get("shapes_cap") == 1,
    "distinct<=1": lambda r: int(r.get("distinct_shapes", 999)) <= 1,
    "mlflow_ok": lambda r: r.get("mlflow_ok") is True,
})

# cap2 with a different num_labels: budget 2, head must match
hidden_run("cap2_labels.json", "hc2", {
    "loads_cap_ok": lambda r: r.get("loads_cap_ok") is True,
    "shapes_cap==2": lambda r: r.get("shapes_cap") == 2,
    "distinct<=2": lambda r: int(r.get("distinct_shapes", 999)) <= 2,
    "head_out==12": lambda r: r.get("head_out") == 12,
})

# malformed config: must degrade to defaults, not crash, full report written
hidden_run("malformed.json", "hm", {
    "full report": lambda r: r.get("head_out") == 7,
    "shapes_cap default 3": lambda r: r.get("shapes_cap") == 3,
    "loads_cap_ok": lambda r: r.get("loads_cap_ok") is True,
    "mlflow_port default 8080": lambda r: r.get("mlflow_port") == 8080,
})

# ------------------------------------------------------------------- reward
if FAILURES:
    print(f"{len(FAILURES)} failure(s): {FAILURES}")
    write(0)
else:
    print("ALL CHECKS PASSED")
    write(1)
PY

echo "verifier done (reward=$([ -f /logs/verifier/reward.txt ] && cat /logs/verifier/reward.txt || echo missing))"