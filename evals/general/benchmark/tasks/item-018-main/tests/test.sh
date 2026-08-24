#!/bin/bash
# Verifier for item-018-main.
#   * enforces the single-file edit boundary (only pool.cpp may change),
#   * builds debug + release and requires BOTH to
#       1) exit 0 and print identical stdout (mode parity), and
#       2) match the true ledger computed independently from cases.txt.
# Reward is the sum of the two halves (0.0 .. 1.0).
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
cd /app/cashier

python3 - <<'PY'
import hashlib, os, subprocess, sys

BOUNDARY = {
    "pool.h":     "76d277e5d4165ad54a05c6e76f8e1949",
    "main.cpp":   "90272e04effd8fc796238cf9d6fed77f",
    "Makefile":   "e9d4446fee8e3b8eb9e381791d10f300",
    "cases.txt":  "5fb5825c705b02199480b569fbf995c8",
    "README.md":  "3349d98cecc3d87074868b47beeaef84",
    "check.sh":   "8f0156f550896a3f0c0014d24358acae",
    "reduce.py":  "d3dd602a138f1164f60a90b70511fcd7",
}

def md5(path):
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

def run(args, cwd):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return p.returncode, (p.stdout or "")

reward = 0.0
try:
    # 1) single-file edit boundary -------------------------------------------------
    touched = [name for name, want in BOUNDARY.items()
               if not os.path.exists(name) or md5(name) != want]
    if touched:
        print("BOUNDARY VIOLATION: immutable files changed: %s" % touched)
        open("/logs/verifier/reward.txt", "w").write("0\n")
        sys.exit(0)

    # 2) build both modes ----------------------------------------------------------
    rc_b, _ = run(["make", "-s", "debug", "release"], cwd="/app/cashier")
    if rc_b != 0:
        print("build failed rc=%d" % rc_b)
        open("/logs/verifier/reward.txt", "w").write("0\n")
        sys.exit(0)

    rc_d, out_d = run(["./build/debug/cashier", "--input", "cases.txt"], cwd="/app/cashier")
    rc_r, out_r = run(["./build/release/cashier", "--input", "cases.txt"], cwd="/app/cashier")

    # 3) mode parity: both exit 0 and print identical output -----------------------
    parity = (rc_d == 0 and rc_r == 0 and out_d == out_r)
    if parity:
        reward += 0.5

    # 4) correctness: output equals the true ledger (recomputed from the ops file)
    def reference():
        rows = {}
        out = []
        for ln in open("/app/cashier/cases.txt"):
            t = ln.split()
            if not t:
                continue
            op = t[0]
            if op == "N":
                r = int(t[1]); rows.setdefault(r, [0, b"\x00" * 16])
            elif op == "W":
                r, v = int(t[1]), int(t[2])
                if r in rows: rows[r][0] += v
            elif op == "F":
                rows.pop(int(t[1]), None)
            elif op == "S":
                out.append(str(sum(v[0] for v in rows.values())))
            elif op == "T":
                r = int(t[1])
                if r in rows:
                    out.append("%d %s" % (rows[r][0], rows[r][1].hex()))
        out.append("LIVE %d/16" % len(rows))
        return "\n".join(out) + "\n"

    want = reference()
    correct = (rc_r == 0 and (out_r or "") == want)
    if correct:
        reward += 0.5

    print("parity=%s correct=%s reward=%.2f rc_d=%d rc_r=%d" % (parity, correct, reward, rc_d, rc_r))
    if not parity:
        print("--- debug ---\n%s" % out_d)
        print("--- release ---\n%s" % out_r)
    if not correct:
        print("--- expected ---\n%s" % want)
        print("--- release got ---\n%s" % out_r)
except Exception as e:  # never crash without writing a reward
    print("verifier error: %r" % e)
    reward = 0.0

open("/logs/verifier/reward.txt", "w").write("%.2f\n" % reward)
PY
exit 0