#!/usr/bin/env bash
# dune-hearth verifier (executes-deliverable).
# /app  = deliverable work (bin/prog, Makefile, build.sh)
# /tests = read-only (hidden/... mounted at verify time)
# Every deliverable is executed; reward written to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables exist --------------------------------------------- #
[ -x /app/bin/prog ]   || fail "missing/not executable /app/bin/prog"
[ -f /app/Makefile ]   || fail "missing /app/Makefile"
[ -f /app/build.sh ]   || fail "missing /app/build.sh"
[ "$reward" -eq 0 ] && { echo "0" > /logs/verifier/reward.txt; echo "final-reward=0"; exit 0; }

# ---- 1. make builds all three from a clean tree ------------------------- #
rm -rf /app/bin /app/.cache
if (cd /app && make all) >/tmp/mk_all.log 2>&1; then
  for b in prog prog_omp prog_mpi; do
    [ -x "/app/bin/$b" ] || fail "make all did not produce /app/bin/$b"
  done
else
  fail "make all failed: $(tail -5 /tmp/mk_all.log)"
fi

# ---- 2. link flags are correct ------------------------------------------ #
if command -v ldd >/dev/null 2>&1; then
  ldd /app/bin/prog_omp 2>/dev/null | grep -q libgomp  || fail "prog_omp not linked to OpenMP runtime (libgomp)"
  ldd /app/bin/prog_mpi 2>/dev/null | grep -q -E 'libmpi(\.so)' || fail "prog_mpi not linked to MPI (libmpi)"
  # serial prog must have no external runtime libs (no libgomp/libmpi/etc.)
  ext=$(ldd /app/bin/prog 2>/dev/null | grep '=>' | grep -oE '/[^ ]+\.so(\.|$)' | grep -vE '/libc\.so|/ld-linux|/libm\.so|/libgcc_s\.so|/libstdc\+\+\.so' | sort -u)
  [ -z "$ext" ] || fail "prog has external shared deps: $(echo $ext)"
fi

# ---- 3. cmake configures and builds prog --------------------------------- #
mkdir -p /app/.cmake_log
rm -rf /tmp/hcmk
if (cd /app && cmake -S . -B /tmp/hcmk) >/tmp/cmk_cfg.log 2>&1 \
   && (cmake --build /tmp/hcmk) >>/tmp/cmk_cfg.log 2>&1; then
  [ -x /tmp/hcmk/prog ] || fail "cmake did not produce prog executable"
else
  fail "cmake configure/build failed: $(tail -5 /tmp/cmk_cfg.log)"
fi

# ---- 4. self-test sentinel ----------------------------------------------- #
if (cd /app && make selftest) >/tmp/selftest.log 2>&1; then
  grep -q 'SENTINEL=dune-hearth-ok' /tmp/selftest.log \
    || fail "selftest did not print success sentinel"
else
  fail "make selftest failed: $(tail -5 /tmp/selftest.log)"
fi

# ---- 5. hidden functional correctness (prog + cmake-built + bare PATH) --- #
PY=$(cat <<'PY'
import glob, os, subprocess, sys

def parse(fn):
    vals = []
    with open(fn) as fh:
        for line in fh:
            t = line.strip()
            if not t:
                continue
            try:
                vals.append(float(t))
            except ValueError:
                continue
    return vals

def expected(wfn, sfn):
    w = parse(wfn); s = parse(sfn)
    n = min(len(w), len(s))
    return "%.3f" % sum(w[i]*s[i] for i in range(n))

fails = []
cases = sorted(glob.glob("/tests/hidden/*"))
if not cases:
    print("NO HIDDEN CASES"); sys.exit(0)
for d in cases:
    wfn, sfn = os.path.join(d, "weight.dat"), os.path.join(d, "sample.dat")
    if not (os.path.isfile(wfn) and os.path.isfile(sfn)):
        fails.append(f"{d}: missing weight.dat/sample.dat"); continue
    exp = expected(wfn, sfn)
    for label, prog in [("prog", "/app/bin/prog"),
                        ("cmake-prog", "/tmp/hcmk/prog")]:
        try:
            r = subprocess.run([prog, wfn, sfn], capture_output=True, text=True, timeout=30)
            got = r.stdout.strip()
            if r.returncode != 0 or got != exp:
                fails.append(f"{label} {d}: got {got!r} (rc {r.returncode}) want {exp!r}")
        except Exception as e:
            fails.append(f"{label} {d}: {e!r}")
    # bare PATH invocation from another cwd
    try:
        r = subprocess.run(["prog", wfn, sfn], capture_output=True, text=True, timeout=30,
                           cwd="/tmp")
        if r.returncode != 0 or r.stdout.strip() != exp:
            fails.append(f"PATH-prog {d}: got {r.stdout.strip()!r} (rc {r.returncode}) want {exp!r}")
    except Exception as e:
        fails.append(f"PATH-prog {d}: {e!r}")

# missing-file robustness: must exit nonzero with no stdout
try:
    r = subprocess.run(["/app/bin/prog", "/tmp/nope_w.dat", "/tmp/nope_s.dat"],
                       capture_output=True, text=True, timeout=30)
    if r.returncode == 0 or r.stdout.strip() != "":
        fails.append(f"missing-file: rc {r.returncode} out {r.stdout.strip()!r} (want nonzero, no stdout)")
except Exception as e:
    fails.append(f"missing-file: {e!r}")

# bad-argcount robustness: nonzero exit
try:
    r = subprocess.run(["/app/bin/prog", "onlyone"], capture_output=True, text=True, timeout=30)
    if r.returncode == 0:
        fails.append("bad-argcount: expected nonzero exit")
except Exception as e:
    fails.append(f"bad-argcount: {e!r}")

if fails:
    print(" ; ".join(fails)); sys.exit(1)
print("HIDDEN-CASES-PASS"); sys.exit(0)
PY
)
if python3 -c "$PY"; then :; else fail "hidden functional checks failed (see above)"; fi

# ---- 6. build.sh produces a zstd GNU tar and (re)installs on PATH -------- #
if (cd /app && bash build.sh) >/tmp/build.log 2>&1; then
  arc=/app/dist/dune-hearth-src.tar.zst
  [ -f "$arc" ] || fail "build.sh did not create $arc"
  if command -v zstd >/dev/null 2>&1; then
    zstd -t "$arc" >/dev/null 2>&1 || fail "archive is not valid zstd"
  fi
  members=$(tar --zstd -tf "$arc" 2>/dev/null || true)
  echo "$members" | grep -q 'CMakeLists.txt' || fail "archive missing CMakeLists.txt"
  echo "$members" | grep -q 'src/prog.c'       || fail "archive missing src/prog.c"
else
  fail "build.sh failed: $(tail -5 /tmp/build.log)"
fi

# ---- 7. PATH === /usr/local/bin/prog after (re)install ------------------- #
P=$(command -v prog 2>/dev/null || true)
[ "$P" = "/usr/local/bin/prog" ] || fail "command -v prog -> '$P' (want /usr/local/bin/prog)"
[ -x /usr/local/bin/prog ]       || fail "/usr/local/bin/prog not executable"

# ---- finalize ------------------------------------------------------------ #
echo "final-reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
