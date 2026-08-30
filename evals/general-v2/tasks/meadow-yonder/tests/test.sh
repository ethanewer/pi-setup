#!/bin/bash
# Verifier for "meadow-yonder" (executes-deliverable).
# Checks every /app deliverable, re-runs the reusable programs on hidden
# inputs from /tests/hidden, and writes the reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 - <<'PYEOF'
import os
import re
import subprocess
import sys

failures = []


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


CLIENT_RE = re.compile(r"^[A-Za-z0-9._:\-]+$")


def expected_counts(accesslog):
    total = 0
    uniq = set()
    with open(accesslog, encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            tok = s.split()[0]
            if CLIENT_RE.fullmatch(tok) and any(c.isdigit() for c in tok):
                total += 1
                uniq.add(tok)
    return total, len(uniq)


def frac(i, t):
    return "0.000" if t <= 0 else "%.3f" % (i / t)


# ------------------- 1. access-log parser -----------------------------------
def check_parser(access_log, label):
    if not expect_clean("/app/logstats.py", label + ": logstats.py"):
        return
    if not os.path.exists(access_log):
        failures.append("%s: missing %s" % (label, access_log))
        return
    t, u = expected_counts(access_log)
    want = "total=%d\nunique=%d\n" % (t, u)
    r = run(["python3", "/app/logstats.py", access_log])
    got = r.stdout.decode(errors="replace")
    if r.returncode != 0:
        failures.append("%s: logstats.py exited %d" % (label, r.returncode))
    elif got != want:
        failures.append("%s: logstats stdout %r != %r" % (label, got, want))


def expect_clean(path, label):
    if not os.path.exists(path):
        failures.append("%s: %s missing" % (label, path))
        return False
    if not os.access(path, os.X_OK):
        failures.append("%s: %s not executable" % (label, path))
    return True


# ------------------- 2. fixed CSV normalizer --------------------------------
def check_csvfixed(csv_in, label):
    if not expect_clean("/app/fixed_script.py", label + "/ fixed_script.py"):
        return
    expect = []
    with open(csv_in, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            expect.append(",".join(g.strip() for g in line.split(",")))
    out = "/tmp/fixed_out_%s.csv" % re.sub(r"\W", "_", label)
    r = run(["python3", "/app/fixed_script.py", csv_in, out])
    if r.returncode != 0:
        failures.append("%s: fixed_script.py exited %d" % (label, r.returncode))
        return
    got = read(out)
    if got is None:
        failures.append("%s: fixed_script.py wrote nothing" % label)
        return
    lines = got.splitlines()
    if lines != expect:
        failures.append("%s: fixed_script output %r != %r" % (label, lines, expect))
    if any(not x for x in lines):
        failures.append("%s: fixed_script output contains a blank line" % label)


# ------------------- 3. cluster sampler ------------------------------------
ROW_RE = re.compile(r"^\d+,\d+,\d+,\d\.\d{3}$")


def check_logrows(logfile, expect_n, label):
    if not os.path.exists(logfile):
        failures.append("%s: %s missing" % (label, logfile))
        return False
    txt = read(logfile)
    if txt is None:
        failures.append("%s: %s unreadable" % (label, logfile))
        return False
    rows = [ln for ln in txt.splitlines() if ln.strip()]
    if len(rows) != expect_n:
        failures.append("%s: expected %d rows, got %d" % (label, expect_n, len(rows)))
        return False
    prev_ts = -1
    for ln in rows:
        if not ROW_RE.fullmatch(ln):
            failures.append("%s: malformed row %r" % (label, ln))
            continue
        ts, total, idle, fr = ln.split(",")
        total, idle = int(total), int(idle)
        if not (0 <= idle <= total):
            failures.append("%s: idle/total inconsistent in %r" % (label, ln))
        if fr != frac(idle, total):
            failures.append("%s: fraction %s != %s in %r" % (label, fr, frac(idle, total), ln))
        if int(ts) <= prev_ts:
            failures.append("%s: timestamps not strictly increasing" % label)
        prev_ts = int(ts)
    return True


def sum_idle(clog):
    s = 0
    txt = read(clog)
    if txt:
        for ln in txt.splitlines():
            p = ln.split(",")
            if len(p) >= 3 and p[2].isdigit():
                s += int(p[2])
    return s


def unique_of(report):
    txt = read(report)
    if txt:
        m = re.search(r"unique=(\d+)", txt)
        if m:
            return int(m.group(1))
    return 0


def check_answer_text(path, expected, label):
    if not os.path.exists(path):
        failures.append("%s: %s missing" % (label, path))
        return
    raw = read(path)
    got = raw.strip() if raw is not None else None
    if got is None or re.fullmatch(r"\d+", got) is None:
        failures.append("%s: %s content %r not a bare integer line" % (label, path, got))
    elif got != "%d" % expected:
        failures.append("%s: %s = %s != %d" % (label, path, got, expected))


def check_compute(clog, rep, label):
    if not expect_clean("/app/compute_answer.py", label + "/ compute_answer.py"):
        return
    out = "/tmp/ans_%s.txt" % re.sub(r"\W", "_", label)
    r = run(["python3", "/app/compute_answer.py", clog, rep, out])
    got = r.stdout.decode(errors="replace").strip()
    exp = sum_idle(clog) + unique_of(rep)
    if r.returncode != 0:
        failures.append("%s: compute_answer.py exited %d" % (label, r.returncode))
    elif re.fullmatch(r"\d+", got) is None:
        failures.append("%s: compute_answer out %r not a bare integer" % (label, got))
    elif got != "%d" % exp:
        failures.append("%s: compute_answer out %r != %d" % (label, got, exp))
    else:
        wrote = read(out)
        if wrote is None or wrote.strip() != got:
            failures.append("%s: compute_answer outfile mismatch" % label)


# ================== MAIN / shipped deliverables ==============================
# report.txt produced by logstats on the shipped log
check_parser("/app/data/access.log", "main")
if not os.path.exists("/app/report.txt"):
    failures.append("main: deliverable /app/report.txt missing")
else:
    t, u = expected_counts("/app/data/access.log")
    want = "total=%d\nunique=%d\n" % (t, u)
    if read("/app/report.txt") != want:
        failures.append("main: report.txt %r != %r" % (read("/app/report.txt"), want))

check_csvfixed("/app/data/records.csv", "main")

if not expect_clean("/app/sample_cluster.sh", "main/sample_cluster.sh"):
    pass
if not os.path.exists("/app/cluster.log"):
    failures.append("main: deliverable /app/cluster.log missing")
else:
    check_logrows("/app/cluster.log", 5, "main-cluster")

# shipped answer.txt exact value
exp_answer = sum_idle("/app/cluster.log") + unique_of("/app/report.txt")
check_answer_text("/app/answer.txt", exp_answer, "main")
# and the reusable computer agrees on shipped data
check_compute("/app/cluster.log", "/app/report.txt", "main-compute")

# ================== HIDDEN scenarios ========================================
hidden = sorted(
    d for d in os.listdir("/tests/hidden")
    if os.path.isdir(os.path.join("/tests/hidden", d))
    and os.path.exists(os.path.join("/tests/hidden", d, "access.log"))
    and os.path.exists(os.path.join("/tests/hidden", d, "records.csv"))
)
if not hidden:
    failures.append("no hidden case directories found")

for tag in hidden:
    hdir = "/tests/hidden/%s" % tag

    check_parser(os.path.join(hdir, "access.log"), tag)

    check_csvfixed(os.path.join(hdir, "records.csv"), tag)

    probe = os.path.join(hdir, "probe.sh")
    hlog = "/tmp/hlog_%s.log" % tag
    hstate = "/tmp/hstate_%s.txt" % tag
    if not os.path.exists(probe):
        failures.append("%s: missing probe.sh" % tag)
    else:
        r = run(["bash", "/app/sample_cluster.sh", "3", "1", hlog, probe, hstate])
        if r.returncode != 0:
            failures.append("%s: sample_cluster.sh exited %d" % (tag, r.returncode))
        else:
            check_logrows(hlog, 3, tag)

    # hidden answer: rebuild via the hidden sampler log + hidden unique count
    rep = "/tmp/hrep_%s.txt" % tag
    if os.path.exists("/app/logstats.py"):
        rp = run(["python3", "/app/logstats.py", os.path.join(hdir, "access.log")])
        with open(rep, "w") as f:
            f.write(rp.stdout.decode(errors="replace"))
    else:
        with open(rep, "w") as f:
            f.write("total=0\nunique=0\n")
    if os.path.exists(hlog):
        check_compute(hlog, rep, tag + "-answer")

# ================== result ==================================================
if failures:
    print("FAILURES (%d):" % len(failures))
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as f:
        f.write("0")
    sys.exit(0)

print("ALL PASS")
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1")
sys.exit(0)
PYEOF