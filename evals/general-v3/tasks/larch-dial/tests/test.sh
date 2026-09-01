#!/bin/bash
# Verifier for larch-dial (executes-deliverable).
# Executes /app/solve.py on the visible fixture and on every hidden fixture,
# asserting the report contract (fscore, pass_count, cap-bounded sequence,
# compiled/edited digests, protected-file immutability) plus the source-size
# ceiling and the dependency/CLI constraints. Writes reward to
# /logs/verifier/reward.txt (1 = all pass, 0 = any fail).
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing deliverable /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import ast
import gzip
import json
import os
import shutil
import subprocess
import sys

SOL = "/app/solve.py"
SIZECAP = 2400  # gzip-compressed byte ceiling for the source
failures = []


def fail(msg):
    failures.append(msg)


def check_bytes(cond, msg):
    if not cond:
        fail(msg)


def shas(path):
    import hashlib
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_deliverable(args):
    r = subprocess.run([sys.executable, SOL] + args,
                       capture_output=True, text=True)
    return r


def compare_hidden(got, want, label):
    for k, v in want.items():
        if k not in got:
            fail("%s: missing key %r" % (label, k))
            continue
        if isinstance(v, float):
            if abs(float(got[k]) - v) > 1e-6:
                fail("%s: %s=%r want %r" % (label, k, got[k], v))
        elif got[k] != v:
            fail("%s: %s=%r want %r" % (label, k, got[k], v))
    check_bytes(len(str(got.get("sequence", ""))) <= int(got.get("cap", 0)),
                "%s: sequence length %d exceeds cap %d" %
                (label, len(str(got.get("sequence", ""))), int(got.get("cap", 0))))


# ---- 1) source-size ceiling (C-90ef6364) ----
sz = len(gzip.compress(open(SOL, "rb").read()))
check_bytes(sz <= SIZECAP, "solve.py gzip=%d exceeds cap %d" % (sz, SIZECAP))

# ---- 2) dependency constraint (C-8c2c83d5): only stdlib imports ----
trees = ast.parse(open(SOL).read())
imports = set()
for node in ast.walk(trees):
    if isinstance(node, ast.Import):
        for a in node.names:
            imports.add(a.name.split(".")[0])
    elif isinstance(node, ast.ImportFrom) and node.module:
        imports.add(node.module.split(".")[0])
bad = sorted(i for i in imports if i not in sys.stdlib_module_names)
check_bytes(not bad, "non-stdlib imports: %s" % bad)

# ---- 3) CLI/config constraint (C-d06efab8): driven only by argv ----
src = open(SOL).read()
check_bytes("sys.argv" in src, "solve.py does not read argv")
for hard in ("/app/project", "/app/weights.json", "/app/inputs.csv"):
    check_bytes(hard not in src, "hard-coded path %s" % hard)

# ---- 4) visible case ----
if not os.path.exists("/app/answer.json"):
    fail("deliverable /app/answer.json missing")
    want = None
else:
    with open("/app/answer.json") as fh:
        want = json.load(fh)
    with open("/tests/expected.json") as fh:
        vis_expect = json.load(fh)
    compare_hidden(want, vis_expect, "visible-answer")

# 4b) re-run the deliverable on the pristine visible fixture
r = run_deliverable(["/app/project", "/app/weights.json",
                     "/app/inputs.csv", "/tmp/vis.json"])
check_bytes(r.returncode == 0, "visible run failed: " + r.stderr.strip())
if os.path.exists("/tmp/vis.json"):
    with open("/tmp/vis.json") as fh:
        vis_re = json.load(fh)
    compare_hidden(vis_re, vis_expect, "visible-rerun")
    # immutability: protected files must match the pristine digests
    check_bytes(shas("/app/project/config/main.txt") == vis_expect["main_sha256"],
                "visible main.txt changed")
    check_bytes(shas("/app/project/config/synonyms.txt") == vis_expect["synonyms_sha256"],
                "visible synonyms.txt changed")
    check_bytes(os.path.exists("/app/project/config/incr.edited.txt"),
                "visible incr.edited.txt not produced")
    check_bytes(os.path.exists("/app/project/config/compiled.txt"),
                "visible compiled.txt not produced")

# ---- 5) hidden cases (fresh fixture sets) ----
os.makedirs("/tmp/ldrun", exist_ok=True)
hidden = "/tests/hidden"
hidden_cases = sorted(
    n for n in os.listdir(hidden) if os.path.isdir(os.path.join(hidden, n)))
check_bytes(len(hidden_cases) >= 2, "expected >=2 hidden cases")
for case in hidden_cases:
    want_path = os.path.join(hidden, case, "expected.json")
    if not os.path.exists(want_path):
        fail("no expectation for " + case)
        continue
    with open(want_path) as fh:
        exp = json.load(fh)
    # copy to a writable working dir so edits can be produced
    work = "/tmp/ldrun/%s" % case
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(os.path.join(hidden, case), work)
    out = "/tmp/ldrun/%s_out.json" % case
    r = run_deliverable([os.path.join(work, "project"),
                         os.path.join(work, "weights.json"),
                         os.path.join(work, "inputs.csv"), out])
    if r.returncode != 0:
        fail("%s: runtime error: %s" % (case, r.stderr.strip()))
        continue
    with open(out) as fh:
        got = json.load(fh)
    compare_hidden(got, exp, case)
    # immutability vs pristine hidden fixture
    pfx = os.path.join(hidden, case, "project", "config")
    wfx = os.path.join(work, "project", "config")
    check_bytes(shas(os.path.join(wfx, "main.txt")) == shas(os.path.join(pfx, "main.txt")),
                "%s: main.txt changed" % case)
    check_bytes(shas(os.path.join(wfx, "synonyms.txt")) == shas(os.path.join(pfx, "synonyms.txt")),
                "%s: synonyms.txt changed" % case)
    check_bytes(os.path.exists(os.path.join(wfx, "incr.edited.txt")),
                "%s: incr.edited.txt not produced" % case)

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)
print("ALL PASS (source gzip=%d)" % sz)
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY