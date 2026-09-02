#!/bin/bash
# Verifier for kite-yonder (executes-deliverable).
#
# Runs every deliverable and the whole native C/C++ stack against hidden /
# fresh cases:
#   1) /app/solve.py is executed to (re)generate /app/answer.json (the primary
#      deliverable) and must exit 0.
#   2) the C argmax sampler is run on hidden weight files; continuation tokens
#      are compared byte-for-byte and documented malformed inputs must fail.
#   3) the C++11 constexpr port is recompiled under -std=c++11 and its values
#      are checked on fresh (N, x) hidden cases.
#   4) the sim Makefile's `serial` and `pgen` targets are re-run; both binaries
#      must show genuine motion with identical checksums and the OpenMP build
#      must actually hedge a (>1) thread pool within a sane run-time band.
#   5) the CMake build must emit LLVM bitcode for every translation unit and a
#      single unified.bc exposing the project's symbols.
#   6) the native<->Python binding call must succeed.
# Reward is 1 only if every check passes; writes /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, re, subprocess, sys

APP = "/app"
problems = []

def run(argv, **kw):
    return subprocess.run(argv, capture_output=True, text=True, **kw)

# ---------- 1) execute the primary deliverable: solve.py -> answer.json -------
if not os.path.isfile(APP + "/solve.py"):
    problems.append("missing /app/solve.py")
else:
    if os.path.exists(APP + "/answer.json"):
        os.remove(APP + "/answer.json")
    r = run(["python3", APP + "/solve.py"])
    if r.returncode != 0:
        problems.append("solve.py exit %d: %s" % (r.returncode, r.stderr[:300]))
    elif not os.path.isfile(APP + "/answer.json"):
        problems.append("solve.py did not rebuild /app/answer.json")
    else:
        try:
            json.load(open(APP + "/answer.json"))
        except Exception as e:
            problems.append("answer.json invalid: %s" % e)

# ---------- 2) hidden sampler cases -------------------------------------------
if not os.path.exists(APP + "/gen/sampler"):
    problems.append("sampler binary missing")
else:
    hd = "/tests/hidden"
    for name in sorted(os.listdir(hd)):
        d = os.path.join(hd, name)
        if not os.path.isdir(d):
            continue
        w = os.path.join(d, "weights.json")
        prompt = open(os.path.join(d, "prompt.txt")).read().strip()
        length = open(os.path.join(d, "length.txt")).read().strip()
        want = open(os.path.join(d, "expected.txt")).read().strip()
        argv = [APP + "/gen/sampler", w, length] + prompt.split()
        r = run(argv)
        if want == "ERROR":
            if r.returncode == 0:
                problems.append("%s: expected failure but exit 0" % name)
            elif not r.stderr.strip():
                problems.append("%s: failed with no diagnostic" % name)
        elif want == "EMPTY":
            if r.returncode != 0 or r.stdout.strip():
                problems.append("%s: expected empty ok, got rc=%d out=%r"
                                % (name, r.returncode, r.stdout))
        else:
            got = " ".join(r.stdout.split())
            want = " ".join(want.split())
            if r.returncode != 0 or got != want:
                problems.append("%s: got rc=%d out=%r want=%r"
                                % (name, r.returncode, r.stdout.strip(), want))

# ---------- 3) C++11 constexpr port ----------
def series(N, x):
    v = 0
    for k in range(1, N + 1):
        v = v * x + k
    return v

head = os.path.join(APP, "tpl", "series.hpp")
hidden_cases = [(6, 5), (10, 2), (3, -7), (15, 1), (0, 4)]
if not os.path.isfile(head):
    problems.append("missing /app/tpl/series.hpp")
else:
    for (n, x) in hidden_cases:
        src = '#include "series.hpp"\n#include <cstdio>\n'
        src += 'constexpr long V = mstr::series<%d,long>(%d);\n' % (n, x)
        src += 'static_assert(V==%d, "exact");\n' % series(n, x)
        src += 'int main(){std::printf("%lld\\n",(long long)V);}\n'
        sp = "/tmp/cc_case.cpp"
        open(sp, "w").write(src)
        cr = run(["g++", "-std=c++11", "-pedantic-errors", "-Wall", "-Werror",
                  "-I%s/tpl" % APP, sp, "-o", "/tmp/cc_case"])
        if cr.returncode != 0:
            problems.append("cpp11 hidden (%d,%d) did not compile: %s"
                            % (n, x, cr.stderr[:300]))
        else:
            rr = run(["/tmp/cc_case"])
            if rr.stdout.strip() != str(series(n, x)):
                problems.append("cpp11 hidden (%d,%d): got %r want %d"
                                % (n, x, rr.stdout.strip(), series(n, x)))

# ---------- 4) sim serial + parallel via Makefile ------------------------------
sim = os.path.join(APP, "sim")
if not os.path.isfile(os.path.join(sim, "Makefile")):
    problems.append("missing /app/sim/Makefile")
else:
    mr = run(["make", "-C", sim, "serial", "pgen"])
    if mr.returncode != 0:
        problems.append("make serial pgen failed: %s" % mr.stderr[:300])
    else:
        pexist = os.path.exists(os.path.join(sim, "serial"))
        peexist = os.path.exists(os.path.join(sim, "pgen"))
        if not (pexist and peexist):
            problems.append("make did not produce serial and pgen")
        else:
            N, S, seed = "120000", "1500", "3000"
            def ck(binpath, extra_env=None):
                env = None
                if extra_env:
                    env = dict(os.environ)
                    env.update(extra_env)
                r = run([os.path.join(sim, binpath), N, S, seed], env=env)
                m = None
                if r.returncode == 0:
                    m = {}
                    for kv in r.stdout.split():
                        k, _, v = kv.partition("=")
                        m[k] = v
                return r, m
            rs, ms = ck("serial")
            rp, mp = ck("pgen", {"OMP_NUM_THREADS": "4"})
            if ms is None: problems.append("serial run failed")
            if mp is None: problems.append("pgen run failed")
            if ms and mp:
                if ms["init"] != mp["init"] or ms["final"] != mp["final"]:
                    problems.append("serial and OMP physics diverge (%s,%s) vs (%s,%s)"
                                    % (ms["init"], ms["final"], mp["init"], mp["final"]))
                if ms["init"] == ms["final"]:
                    problems.append("no genuine motion (init==final)")
                try:
                    if int(mp["threads"]) < 2:
                        problems.append("parallel build not actually threaded (threads=%s)" % mp["threads"])
                    st = float(ms["ms"]); pt = float(mp["ms"])
                    if pt <= 0 or pt > st * 15.0:
                        problems.append("speed band violated serial=%.2f parallel=%.2f" % (st, pt))
                except ValueError:
                    problems.append("unparseable sim timings")

# ---------- 5) LLVM IR emission ----------
bc = os.path.join(APP, "cir", "build", "bc")
unified = os.path.join(bc, "unified.bc")
for t in ("alpha", "beta", "gamma"):
    if not os.path.exists(os.path.join(bc, t + ".bc")):
        problems.append("missing per-TU bitcode " + t + ".bc")
if not os.path.exists(unified):
    problems.append("missing unified.bc")
else:
    nm = run(["llvm-nm", unified])
    if nm.returncode != 0:
        problems.append("unified.bc not valid LLVM bitcode: %s" % nm.stderr[:200])
    else:
        for sym in ("ring_radius_r", "beta_quant", "gamma_sep"):
            if not re.search(r"\bT\s+" + sym + r"\b", nm.stdout):
                problems.append("unified.bc missing symbol %s" % sym)

# ---------- 6) binding call succeeds ----------
br = run(["python3", APP + "/bind/bad.py"])
if br.returncode != 0 or "ok" not in br.stdout:
    problems.append("binding call failed: rc=%d out=%r" % (br.returncode, br.stdout))

if problems:
    for p in problems:
        print("FAIL:", p)
    sys.exit(1)
print("ALL_OK")
PY
if [ $? -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0