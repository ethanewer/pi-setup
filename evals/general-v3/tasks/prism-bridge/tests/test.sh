#!/bin/bash
#
# Verifier for prism-bridge.
#   A. deliverables present (mpi_main.c, serve.py, markers/).
#   B. compiles /app/mpi_main.c and runs it (serial np=1 vs parallel np=4) on
#      the visible dataset and EVERY hidden MPI dataset, asserting that the
#      parallel contig set equals the serial contig set and that all 4 ranks
#      produced non-empty output.
#   C. re-runs /app/serve.py on every hidden file directory, recomputing the
#      PBKDF2 manifest independently and requiring the three worker marker
#      files to be (re)created with >=2 distinct worker PIDs (process-pool
#      evidence), plus a static check that serve.py uses a process pool, not a
#      thread pool.
#   D. verifies the installed hadoop 3.3.6 + java 11 via /app/serve.py --status
#      AND independently on disk.
#
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
ok=1
fail(){ echo "FIELD: $*"; ok=0; }
HIDDEN=/tests/hidden

# ---------- A. deliverables ----------
[ -f /app/mpi_main.c ]    || fail "missing /app/mpi_main.c"
[ -f /app/serve.py ]      || fail "missing /app/serve.py"
[ -d /app/markers ]       || fail "missing /app/markers/"

# ---------- B. MPI: serial == parallel on all datasets ----------
if ! mpicc -O2 /app/mpi_main.c -o /tmp/mpi_sim 2>/tmp/mpicc.err; then
  fail "mpicc compile failed: $(tail -3 /tmp/mpicc.err)"
else
  check_mpi() { # $1=input, $2=label
    rm -rf /tmp/mpi_ser /tmp/mpi_par
    mkdir -p /tmp/mpi_ser /tmp/mpi_par
    mpirun --allow-run-as-root --oversubscribe -np 1 /tmp/mpi_sim "$1" /tmp/mpi_ser >/tmp/m1.log 2>&1
    mpirun --allow-run-as-root --oversubscribe -np 4 /tmp/mpi_sim "$1" /tmp/mpi_par >/tmp/m4.log 2>&1
    python3 - "$2" <<'PY' || fail "MPI case $2: serial!=parallel or empty rank"
import os, sys
label = sys.argv[1]
def contigs(d):
    out=[]
    if not os.path.isdir(d): return out
    for fn in os.listdir(d):
        out += open(os.path.join(d,fn)).read().splitlines()
    return sorted(out)
ser = contigs("/tmp/mpi_ser"); par = contigs("/tmp/mpi_par")
if ser != par:
    print("  mismatch", label, len(ser), len(par)); sys.exit(1)
ranks = os.listdir("/tmp/mpi_par")
nonempty = [r for r in ranks if os.path.getsize("/tmp/mpi_par/"+r) > 0]
if len(nonempty) < 4:
    print("  not all 4 ranks produced output:", sorted(ranks)); sys.exit(1)
PY
  }
  check_mpi /app/sample/reads.mpi.txt visible
  if [ -d "$HIDDEN" ]; then
    for h in "$HIDDEN"/*.mpi.txt; do
      [ -e "$h" ] || continue
      check_mpi "$h" "$(basename "$h")"
    done
  fi
fi

# ---------- C. serve.py on hidden file dirs (manifest + markers) ----------
python3 - <<'PY' || fail "serve.py static evidence: must be a process pool"
src = open("/app/serve.py").read()
assert "ProcessPoolExecutor" in src, "no ProcessPoolExecutor"
assert "ThreadPoolExecutor" not in src, "uses a thread pool instead of processes"
PY

check_serve() { # $1=input_dir, $2=label
  rm -rf /app/markers
  python3 /app/serve.py "$1" /tmp/mani.txt >/tmp/serve.log 2>&1 || { fail "serve case $2: non-zero exit"; return; }
  python3 - "$1" /tmp/mani.txt "$2" <<'PY' || { fail "serve case $2: manifest/marker mismatch"; return; }
import hashlib, os, sys
indir, manpath, label = sys.argv[1], sys.argv[2], sys.argv[3]
files = sorted(f for f in os.listdir(indir) if os.path.isfile(os.path.join(indir, f)))
def pb(rel):
    with open(rel,'rb') as fh: data=fh.read()
    salt = hashlib.sha256(os.path.basename(rel).encode()).digest()
    return os.path.basename(rel), hashlib.pbkdf2_hmac('sha256', data, salt, 60000).hex()
exp = sorted(n+"\t"+h for n,h in (pb(os.path.join(indir, f)) for f in files))
got = open(manpath).read().splitlines()
assert got == exp, (label, got, exp)
# markers: exactly the three, non-empty, >=2 distinct worker PIDs
mdir = "/app/markers"
if not os.path.isdir(mdir): raise AssertionError("no markers dir")
names = set(os.listdir(mdir))
assert names == {"STARTED.marker","WORKERS.marker","COMPLETED.marker"}, (label, names)
pids = []
for ln in open(os.path.join(mdir,"WORKERS.marker")):
    pids.append(int(ln.split()[1]))
assert len(set(pids)) >= 2, (label, pids)
for n in names:
    assert os.path.getsize(os.path.join(mdir,n)) > 0, (label, n)
PY
}

if [ -d "$HIDDEN" ]; then
  for d in "$HIDDEN"/serve_dir*/; do
    [ -d "$d" ] || continue
    check_serve "$d" "$(basename "$d")"
  done
fi
# deliverable markers must also exist in the left-behind state
[ -d /app/markers ] || fail "markers not created"
python3 - <<'PY' || fail "left-behind markers missing a required marker"
import os
want={"STARTED.marker","WORKERS.marker","COMPLETED.marker"}
if not os.path.isdir("/app/markers"): raise SystemExit(1)
have=set(os.listdir("/app/markers"))
if not want.issubset(have): raise SystemExit(1)
PY

# ---------- D. hadoop 3.3.6 + java 11 ----------
python3 /app/serve.py --status > /tmp/status.txt 2>&1 || fail "serve.py --status failed"
python3 - <<'PY' || fail "status report: wrong java/hadoop versions"
import re
s = open("/tmp/status.txt").read()
print("  status:\n" + "\n".join("    "+l for l in s.splitlines()))
jm = re.search(r'^java\s+(\d+\.\d+)', s, re.M)
hm = re.search(r'^hadoop\s+([\d.]+)', s, re.M)
assert jm and jm.group(1).startswith("11."), ("java major", jm)
assert hm and hm.group(1) == "3.3.6", ("hadoop", hm)
PY
# independent on-disk checks
java -version >/dev/null 2>/tmp/jver.txt || fail "java missing"
grep -q '"11\.' /tmp/jver.txt || fail "java is not major 11: $(head -1 /tmp/jver.txt)"
JH=$(dirname $(dirname $(realpath $(which java))))
JAVA_HOME="$JH" /opt/hadoop/bin/hadoop version >/tmp/hver.txt 2>&1 || fail "hadoop version failed"
grep -q "Hadoop 3.3.6" /tmp/hver.txt || fail "hadoop is not 3.3.6"

# ---------- reward ----------
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
