#!/bin/bash
# marlin-forge verifier: recompiles /app/assembly_upc.c, executes the binary on
# every hidden case (including malformed-argv cases), then runs the visible
# case and byte-checks the /app/worker_*.dat deliverables. Writes reward (1/0)
# to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import glob, json, os, re, subprocess, tempfile

failures = []
def fail(m):
    failures.append(m)
    print("FAIL:", m)

SRCF = "/app/assembly_upc.c"
BIN = "/app/agen"

def value_of(i):
    return (i * 4453 + 911) % 65521

def item_total(lo, hi):
    return sum(value_of(i) for i in range(lo, hi))

for p in (SRCF, BIN):
    if not os.path.isfile(p):
        fail("missing deliverable " + p)

built = None
if os.path.isfile(SRCF):
    built = os.path.join(tempfile.mkdtemp(prefix="mf_build_"), "agen")
    r = subprocess.run(["gcc", "-O2", "-pthread", "-o", built, SRCF],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        fail("cannot compile /app/assembly_upc.c: %s" % (r.stderr or "")[:300])
        built = None

FMT = re.compile(r"worker=(\d+)\nspan=(\d+):(\d+)\nsum=(\d+)\nmax=(\d+)\nvalid=true\r?\n?")

def check_run(binary, R_, items, label):
    work = tempfile.mkdtemp(prefix="mf_run_")
    try:
        r = subprocess.run([binary, str(R_), str(items)], cwd=work,
                           capture_output=True, timeout=120)
    except Exception as e:
        fail("%s: run raised %r" % (label, e)); return
    if r.returncode != 0:
        fail("%s: exited %d" % (label, r.returncode)); return
    outs = sorted(glob.glob(os.path.join(work, "worker_*.dat")))
    if len(outs) != R_:
        fail("%s: produced %d worker files, expected %d" % (label, len(outs), R_)); return
    for rnum in range(R_):
        fname = os.path.join(work, "worker_%d.dat" % rnum)
        if not os.path.isfile(fname):
            fail("%s: missing worker_%d.dat" % (label, rnum)); return
        try:
            content = open(fname, encoding="utf-8", errors="replace").read()
        except Exception as e:
            fail("%s: unreadable worker_%d.dat: %r" % (label, rnum, e)); return
        m = FMT.fullmatch(content)
        if not m:
            fail("%s: worker_%d.dat format wrong: %r" % (label, rnum, content[:200])); return
        lo = (items * rnum) // R_
        hi = (items * (rnum + 1)) // R_
        vals = [value_of(i) for i in range(lo, hi)]
        want = [rnum, lo, hi, item_total(lo, hi), max(vals) if vals else 0]
        got = [int(v) for v in m.groups()]
        if got != want:
            fail("%s: worker_%d got %r want %r" % (label, rnum, got, want)); return

if built:
    hroot = "/tests/hidden"
    files = sorted(glob.glob(os.path.join(hroot, "assembly_*.json"))) if os.path.isdir(hroot) else []
    if len(files) < 3:
        fail("expected >= 3 hidden case files, found %d" % len(files))
    for p in files:
        try:
            c = json.load(open(p))
        except Exception as e:
            fail("%s unreadable: %r" % (p, e)); continue
        if c.get("kind") == "assembly_bad":
            for argv in c.get("argv", []):
                work = tempfile.mkdtemp(prefix="mf_bad_")
                try:
                    r = subprocess.run([built] + [str(a) for a in argv], cwd=work,
                                       capture_output=True, timeout=120)
                except Exception as e:
                    fail("assembly_bad argv %r raised %r" % (argv, e)); continue
                if r.returncode == 0:
                    fail("assembly_bad argv %r exited 0" % (argv,)); continue
                if glob.glob(os.path.join(work, "worker_*.dat")):
                    fail("assembly_bad argv %r wrote worker files" % (argv,)); continue
        elif c.get("kind") == "assembly":
            check_run(built, int(c["num_threads"]), int(c["items"]),
                      "assembly:%s" % os.path.basename(p))
        else:
            fail("%s unknown kind %r" % (p, c.get("kind")))

    # Visible case re-executed, plus the /app worker_*.dat deliverables.
    check_run(built, 4, 37, "visible-rerun")
    rank_files = sorted(glob.glob("/app/worker_*.dat"))
    if len(rank_files) != 4:
        fail("expected 4 /app/worker_*.dat from ./agen 4 37, got %d" % len(rank_files))
    else:
        for rnum in range(4):
            fname = "/app/worker_%d.dat" % rnum
            if fname not in rank_files:
                fail("missing deliverable " + fname); continue
            try:
                content = open(fname, encoding="utf-8", errors="replace").read()
            except Exception as e:
                fail("deliverable %s unreadable: %r" % (fname, e)); continue
            m = FMT.fullmatch(content)
            lo = (37 * rnum) // 4
            hi = (37 * (rnum + 1)) // 4
            vals = [value_of(i) for i in range(lo, hi)]
            want = [rnum, lo, hi, item_total(lo, hi), max(vals) if vals else 0]
            if not m or [int(v) for v in m.groups()] != want:
                fail("deliverable %s content wrong: %r" % (fname, content[:200]))

print("failures:", len(failures))
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not failures else "0")
PY
exit 0
