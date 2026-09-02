#!/bin/bash
# Verifier for pearl-scroll: executes /app/edit_stream.py on visible + hidden inputs.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import hashlib, json, os, subprocess, sys

TOOL = "/app/edit_stream.py"
BASE = "/tests/hidden"
TMP = "/tmp/v"
os.makedirs(TMP, exist_ok=True)

failures = []
def check(cond, msg):
    if not cond:
        failures.append(msg)

def sha_file(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def manifest(p):
    with open(p) as f:
        return json.load(f)

def run_tool(src, edits, out_txt, out_mf):
    return subprocess.run([sys.executable, TOOL, src, edits, out_txt, out_mf],
                          capture_output=True, text=True)

VIS_SHA = "35143892a4d192b2513f79caa2a96fb11f84762f87e925b862df4d47cb19783f"
VIS_LEN = 23

# ---------- 1) deliverable exists ----------
if not os.path.isfile(TOOL):
    open("/logs/verifier/reward.txt", "w").write("0")
    print("FAIL: /app/edit_stream.py missing")
    sys.exit(0)

# ---------- 2. visible case: run the tool on the provided inputs ----------
vo = os.path.join(TMP, "vis.txt"); vm = os.path.join(TMP, "vis.json")
p = run_tool("/app/source.txt", "/app/edits.json", vo, vm)
check(p.returncode == 0, "visible run failed: %s" % p.stderr.strip())
if os.path.isfile(vo):
    check(sha_file(vo) == VIS_SHA, "visible output sha mismatch")
if os.path.isfile(vm):
    m = manifest(vm)
    check(m.get("sha256") == VIS_SHA, "visible manifest sha mismatch")
    check(m.get("byte_length") == VIS_LEN, "visible manifest length mismatch")

# named deliverables must exist and be the correct result
check(os.path.isfile("/app/edited.txt"), "/app/edited.txt missing")
if os.path.isfile("/app/edited.txt"):
    check(sha_file("/app/edited.txt") == VIS_SHA, "/app/edited.txt content wrong")
check(os.path.isfile("/app/manifest.json"), "/app/manifest.json missing")
if os.path.isfile("/app/manifest.json"):
    m = manifest("/app/manifest.json")
    check(m.get("sha256") == VIS_SHA, "/app/manifest.json sha wrong")
    check(m.get("byte_length") == VIS_LEN, "/app/manifest.json length wrong")

# the visible source input must not have been modified by the agent or the tool
check(os.path.isfile("/app/source.txt"), "visible source missing")
if os.path.isfile("/app/source.txt"):
    check(sha_file("/app/source.txt") ==
          "aa9127b6ec21c6bb2f78d5ca1ba4e143bc188fe88ace4f8bda763ef274091c46", "source.txt modified")

# ---------- 3. hidden cases h1..h4: fresh inputs, compare to ground truth ----------
for name in ["h1", "h2", "h3", "h4"]:
    d = os.path.join(BASE, name)
    src, ed = os.path.join(d, "source.txt"), os.path.join(d, "edits.json")
    ex_txt, ex_mf = os.path.join(d, "expected.txt"), os.path.join(d, "manifest.json")
    out, mf = os.path.join(TMP, name + ".out"), os.path.join(TMP, name + ".manifest")
    p = run_tool(src, ed, out, mf)
    check(p.returncode == 0, "%s run failed: %s" % (name, p.stderr.strip()))
    if os.path.isfile(out) and os.path.isfile(ex_txt):
        check(sha_file(out) == sha_file(ex_txt), "%s output mismatch" % name)
    if os.path.isfile(mf) and os.path.isfile(ex_mf):
        em, gm = manifest(ex_mf), manifest(mf)
        check(gm.get("sha256") == em.get("sha256"), "%s manifest sha mismatch" % name)
        check(gm.get("byte_length") == em.get("byte_length"), "%s manifest len mismatch" % name)

# ---------- 4. hidden case h5: malformed (overlapping) edits must be rejected ----------
d = os.path.join(BASE, "h5")
p = run_tool(os.path.join(d, "source.txt"), os.path.join(d, "edits.json"),
             os.path.join(TMP, "h5.out"), os.path.join(TMP, "h5.manifest"))
check(p.returncode != 0, "h5: overlapping edits accepted (should exit nonzero)")
check(not os.path.exists(os.path.join(TMP, "h5.out")) or
      os.path.getsize(os.path.join(TMP, "h5.out")) == 0,
      "h5: no output file should be produced on error")

# ---------- 5. hidden case h6: large file streams byte-exact with one edit --------
unit = b"limpid otter roams the fog-shrouded bank for a long while, then sleeps.\n"
a, b = 1400, 1620
big = unit * a
L = len(big)
marker = b"<<<MARK>>>"
src_big = big + marker + unit * b
exp_big = big + b"EDITED!!" + unit * b
srcf = os.path.join(TMP, "h6.src"); edf = os.path.join(TMP, "h6.edits")
outf = os.path.join(TMP, "h6.out"); mff = os.path.join(TMP, "h6.manifest")
with open(srcf, "wb") as f: f.write(src_big)
json.dump([{"start": L, "end": L + len(marker), "text": "EDITED!!"}], open(edf, "w"))
p = run_tool(srcf, edf, outf, mff)
check(p.returncode == 0, "h6 run failed: %s" % p.stderr.strip())
if os.path.isfile(outf):
    check(sha_file(outf) == hashlib.sha256(exp_big).hexdigest() and
          os.path.getsize(outf) == len(exp_big), "h6 large streaming output mismatch")

open("/logs/verifier/reward.txt", "w").write("1" if not failures else "0")
print("ALL CHECKS PASSED" if not failures else "VERIFIER FAILURES:")
if failures:
    for f in failures:
        print("  -", f)
    sys.exit(1)
PY