#!/usr/bin/env bash
# hollow-fathom verifier
set -euo pipefail
mkdir -p /logs/verifier
python3 - <<'PY'
import json, os, subprocess, glob

HID = "/tests/hidden"
failures = []

def check(name, fn):
    try:
        fn()
        print("  pass " + name)
    except Exception as e:
        failures.append(name)
        print("  FAIL " + name + " : " + repr(e))

# ---------------------------------------------------------------- oracle refs
def ref_derive(cluedir):
    base = None
    with open(os.path.join(cluedir, "base.txt")) as f:
        for ln in f:
            s = ln.strip()
            if s:
                base = int(s)
                break
    if base is None:
        raise AssertionError("missing base in " + cluedir)
    val = base
    for p in sorted(glob.glob(os.path.join(cluedir, "step_*"))):
        try:
            lines = [l.strip() for l in open(p) if l.strip() != ""]
            if len(lines) < 2:
                continue
            op = lines[0].lower()
            operand = int(lines[1])
            if op == "add":
                val += operand
            elif op == "sub":
                val -= operand
            elif op == "mul":
                val *= operand
            elif op == "div":
                val //= operand
            elif op == "mod":
                val %= operand
        except Exception:
            continue
    return val

def read_series(path):
    d = {}
    with open(path) as f:
        for ln in f:
            line = ln.strip()
            if not line:
                continue
            parts = [x.strip() for x in line.split(",")]
            if len(parts) < 2 or parts[0] == "key":
                continue
            try:
                v = int(parts[1])
            except ValueError:
                continue
            d[parts[0]] = v
    return d

def ref_report(records):
    ok = []
    for r in records:
        if not isinstance(r, dict):
            continue
        if not isinstance(r.get("id"), str):
            continue
        if not isinstance(r.get("zone"), str):
            continue
        p, s = r.get("prio"), r.get("score")
        if not isinstance(p, (int, float)) or not isinstance(s, (int, float)):
            continue
        if p < 0:
            continue
        ok.append(r)
    rank = {"alpha": 0, "beta": 1, "gamma": 2}
    ok.sort(key=lambda r: (rank.get(r["zone"], 3), r["prio"], r["score"], r["id"]))
    return ["%s|%s|%s|%s" % (r["id"], r["zone"], r["prio"], r["score"]) for r in ok]

# ---------------------------------------------------------------- 1. derive.py
def check_derive():
    assert os.path.isfile("/app/derive.py"), "derive.py missing"
    # default answer.txt must match the derived default payload
    def run_derive(cluedir):
        r = subprocess.run(["python3","/app/derive.py",cluedir],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, "derive.py failed on %s: %s" % (cluedir, r.stderr.decode())
        return int(r.stdout.decode().strip())
    assert run_derive("/app/clues") == ref_derive("/app/clues"), "derive default mismatch"
    assert os.path.isfile("/app/answer.txt"), "answer.txt missing"
    av = open("/app/answer.txt").read().strip()
    assert av == str(ref_derive("/app/clues")), "answer.txt content wrong: %r" % av
    # hidden clue dirs
    for case in sorted(os.listdir(os.path.join(HID,"derive"))):
        cd = os.path.join(HID,"derive",case)
        if not os.path.isdir(cd):
            continue
        got = run_derive(cd)
        assert got == ref_derive(cd), "%s derive: got %s exp %s" % (case, got, ref_derive(cd))
check("derive.py payload + hidden clue dirs", check_derive)

# ---------------------------------------------------------------- 2. diff_series.py
def check_diff():
    assert os.path.isfile("/app/diff_series.py"), "diff_series.py missing"
    base = os.path.join(HID,"series")
    for a in sorted(os.listdir(base)):
        if not a.endswith("_a.csv"):
            continue
        b = a.replace("_a.csv","_b.csv")
        ap, bp = os.path.join(base,a), os.path.join(base,b)
        r = subprocess.run(["python3","/app/diff_series.py",ap,bp],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, "diff_series failed %s: %s" % (a, r.stderr.decode())
        da, db = read_series(ap), read_series(bp)
        diffs = [da[k]-db[k] for k in da if k in db]
        n = len(diffs)
        mean = round(sum(diffs)/n, 4) if n else 0.0
        exp = str(mean)
        got = r.stdout.decode().strip()
        assert got == exp, "%s diff got=%s exp=%s" % (a, got, exp)
check("diff_series.py on hidden pairs", check_diff)

# ---------------------------------------------------------------- 3. report.jq + args
def check_report():
    assert os.path.isfile("/app/report.jq"), "report.jq missing"
    assert os.path.isfile("/app/report_args.json"), "report_args.json missing"
    meta = json.load(open("/app/report_args.json"))
    opts = meta.get("options")
    assert isinstance(opts, list) and len(opts) > 0, "options must be a non-empty list"
    assert all(isinstance(o, str) and o.startswith("-") for o in opts), \
        "every options item must be dash-form: %r" % (opts,)
    prog = meta.get("program")
    assert isinstance(prog, str) and os.path.isfile(prog), "program must be an existing file"
    feeds = sorted(os.listdir(os.path.join(HID,"report")))
    feeds.append("/app/feed.json")
    for fp in feeds:
        fpath = fp if os.path.isabs(fp) else os.path.join(HID,"report",fp)
        r = subprocess.run(["jq"]+opts+["-f",prog,fpath],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert r.returncode == 0, "jq re-run failed on %s: %s" % (fp, r.stderr.decode())
        got = r.stdout.decode().strip().splitlines()
        exp = ref_report(json.load(open(fpath)))
        assert got == exp, "%s report mismatch\n--got--\n%s\n--exp--\n%s" % (fp, got, exp)
check("report.jq + report_args.json regeneration", check_report)

# ---------------------------------------------------------------- reward
reward = 0 if failures else 1
open("/logs/verifier/reward.txt","w").write(str(reward))
print("REWARD=%d failed=%r" % (reward, failures))
PY