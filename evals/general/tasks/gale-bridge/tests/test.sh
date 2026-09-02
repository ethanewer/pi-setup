#!/usr/bin/env bash
# gale-bridge verifier.
set -euo pipefail
mkdir -p /logs/verifier
python3 - <<'PY'
import json, os, re, subprocess

HID = "/tests/hidden"
failures = []

def check(name, fn):
    try:
        fn()
        print("  pass " + name)
    except Exception as e:
        failures.append(name)
        print("  FAIL " + name + " : " + str(e))

# ---------------- oracle helpers ------------------------------------------
def frames_of(path):
    frames = {}
    with open(path) as f:
        for raw in f:
            ln = raw.strip()
            if not ln:
                continue
            parts = [p.strip() for p in ln.split(",")]
            if len(parts) < 3 or parts[0].lower() == "frame":
                continue
            frames.setdefault(int(parts[0]), []).append((int(parts[1]), int(parts[2])))
    return frames

def topk_expected(path, k):
    out = ["frame,bin,magnitude,rank"]
    for fr in sorted(frames_of(path)):
        for r, (b, m) in enumerate(sorted(frames_of(path)[fr], key=lambda t: (-t[1], t[0]))[:k], 1):
            out.append("%d,%d,%d,%d" % (fr, b, m, r))
    return "\n".join(out)

def run_topk(csv_path, k):
    r = subprocess.run(["gawk", "-f", "/app/topk.awk", "-v", "k=%d" % k, csv_path],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert r.returncode == 0, "topk awk failed: " + r.stderr.decode()
    return r.stdout.decode().strip()

# ------------------------------- 1. workbook -------------------------------
def check_workbook():
    nb = json.load(open("/app/workbook.ipynb"))
    assert nb.get("nbformat", 0) >= 4, "nbformat<4"
    types = [c.get("cell_type") for c in nb["cells"]]
    assert "markdown" in types, "no markdown cell"
    assert "code" in types, "no code cell"
    md = " ".join("".join(c.get("source","")) for c in nb["cells"] if c.get("cell_type")=="markdown")
    assert "spectral" in md.lower(), "markdown must mention 'spectral'"
    for c in nb["cells"]:
        if c.get("cell_type") != "code":
            continue
        src = "".join(c.get("source",""))
        if "import matplotlib" in src and re.search(r"plt\.(plot|bar|scatter|step|hist)\(", src):
            p = subprocess.run(["python3","-c",src], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert p.returncode == 0, "plotting code cell failed: "+p.stderr.decode()
            return
    raise AssertionError("no plotting matplotlib code cell found")
check("workbook (markdown + plotting code cell)", check_workbook)

# ------------------------------- 2. vim plugin -----------------------------
def vim_run(cmds, out):
    c = ["vim","-n","-es","-N","-u","NONE","-i","NONE","-c","source /app/plugin.vim"]
    for cmd in cmds:
        c.append("-c"); c.append(cmd)
    c.append("-c"); c.append("GaleReport %s" % out)
    c.append("-c"); c.append("qa!")
    r = subprocess.run(c, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert r.returncode == 0, "vim failed: "+r.stderr.decode()
    return open(out).read().splitlines()

def vim_layout(lines, expected):
    assert lines and lines[0] == "windows=%d" % expected, lines
    toks = lines[1:1+expected]
    assert len(toks) == expected, lines
    seen = set()
    for t in toks:
        m = re.match(r"window=(\d+):rows=(\d+):cols=(\d+)$", t)
        assert m, "bad window line: "+t
        assert int(m.group(2)) >= 1 and int(m.group(3)) >= 1, m.group(0)
        seen.add(int(m.group(1)))
    assert seen == set(range(1, expected+1)), seen

def check_vim():
    vim_layout(vim_run([], "/tmp/v1.txt"), 1)
    vim_layout(vim_run(["split"], "/tmp/v2.txt"), 2)
    vim_layout(vim_run(["split","vsplit"], "/tmp/v3.txt"), 3)
    vim_layout(vim_run(["new","new"], "/tmp/v4.txt"), 3)
check("vim plugin layout (fresh sessions)", check_vim)

# ------------------------------- 3. topk awk ---------------------------------
def check_topk():
    cases = {"case1.csv": 3, "case2.csv": 5, "case3.csv": 1, "case4.csv": 2}
    for name, k in cases.items():
        p = os.path.join(HID, "topk", name)
        got = run_topk(p, k)
        exp = topk_expected(p, k).strip()
        assert got == exp, "%s\n--got--\n%s\n--exp--\n%s" % (name, got, exp)
check("topk.awk ranked across frames", check_topk)

# ------------------------------- 4. jq filter --------------------------------------
def jq_expected(arr):
    out = []
    for r in arr:
        if r.get("status") != "ok":
            continue
        day = r["timestamp"].split("T")[0]
        tags = r.get("tags", [])
        out.append({"id": r["id"], "hue": r["colour"], "day": day,
                    "tagcount": len(tags), "firsttag": (tags[0] if tags else None)})
    out.sort(key=lambda o: (o["day"], o["id"]))
    return out

def check_jq():
    for name in ["case1","case2","case3","case4"]:
        jf = os.path.join(HID, "jq", name + ".json")
        exp = jq_expected(json.load(open(jf)))
        r = subprocess.run(["jq","-S","-f","/app/filter.jq",jf],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, "jq failed: "+r.stderr.decode()
        assert json.loads(r.stdout) == exp, name + " mismatch"
check("jq filter pipeline", check_jq)

# ------------------------------- 5. pipeline ----------------------------------------
def check_pipeline():
    out = "/tmp/gale_full"
    subprocess.run(["/app/pipeline.sh","full",out], check=True)
    mag = os.path.join(out, "magnitudes.csv")
    pk  = os.path.join(out, "peaks.csv")
    assert os.path.isfile(mag) and os.path.isfile(pk), "full-mode outputs missing"
    assert open(pk).read().strip() == topk_expected(mag, 3).strip(), "full-mode peaks mismatch"

    sh = "/tmp/shims"
    os.makedirs(sh, exist_ok=True)
    open(os.path.join(sh,"python3"),"w").write("#!/bin/sh\necho py >> /tmp/py_used\nexit 99\n")
    open(os.path.join(sh,"awk"),"w").write(
        "#!/bin/sh\necho awk >> /tmp/awk_used\nexec /usr/bin/gawk \"$@\"\n")
    os.chmod(os.path.join(sh,"python3"),0o755)
    os.chmod(os.path.join(sh,"awk"),0o755)
    for f in ("/tmp/py_used","/tmp/awk_used"):
        if os.path.exists(f): os.unlink(f)
    magcsv = os.path.join(HID, "pipeline", "case1.csv")
    env = dict(os.environ, PATH=sh + ":" + os.environ["PATH"], TOPK_K="3")
    r = subprocess.run(["/app/pipeline.sh","subset",magcsv,"/tmp/sub.csv"],
                       env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert r.returncode == 0, "subset failed: "+r.stderr.decode()
    assert not os.path.exists("/tmp/py_used"), "subset invoked python!"
    assert os.path.exists("/tmp/awk_used"), "subset did not use awk via PATH"
    assert open("/tmp/sub.csv").read().strip() == topk_expected(magcsv,3).strip(), "subset mismatch"
check("pipeline full + awk-only subset", check_pipeline)

# ------------- reward ------------------------------------------------------
reward = 0 if failures else 1
with open("/logs/verifier/reward.txt","w") as f:
    f.write(str(reward))
print("REWARD=%d failed=%r" % (reward, failures))
PY