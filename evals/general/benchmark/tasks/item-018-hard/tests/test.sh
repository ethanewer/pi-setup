#!/bin/bash
# Verifier for item-018-hard.
#   * enforces the single-file edit boundary (only pool.cpp may change),
#   * builds both modes; requires parity + exact ledger on the visible case,
#   * runs three hidden/adversarial op files (free-then-realloc patterns,
#     exhaustion guards, out-of-range rowids, repeated runs),
#   * requires the isolation artifact (/app/isolation/repro.txt + notes.txt),
#   * checks determinism (two consecutive release runs identical).
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt
cd /app/cashier

python3 - <<'PY'
import hashlib, os, subprocess, sys

BOUNDARY = {
    "pool.h":    "76d277e5d4165ad54a05c6e76f8e1949",
    "main.cpp":  "90272e04effd8fc796238cf9d6fed77f",
    "Makefile":  "e9d4446fee8e3b8eb9e381791d10f300",
    "cases.txt": "5e1b9b3d0408c305da32e679902f6292",
    "README.md": "3349d98cecc3d87074868b47beeaef84",
    "check.sh":  "8f0156f550896a3f0c0014d24358acae",
    "reduce.py": "d3dd602a138f1164f60a90b70511fcd7",
}

def md5(path):
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

def run(args, cwd):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return p.returncode, (p.stdout or "")

def reference(ops_text):
    """True ledger: sum of live row balances for each S; hex tag for T."""
    rows = {}
    out = []
    for ln in ops_text.splitlines():
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

HIDDEN = [
    # 1) free then two allocs (trips a self-linking free list)
    ["N 0", "F 0", "N 1", "N 2", "W 1 4", "W 2 6", "S", "F 1", "F 2", "S"],
    # 2) stress: churn through all 16 cells, never > 8 live
    ["N %d" % (i % 8) for i in range(20)] +
    ["W %d %d" % (i % 8, (i * 3) % 17 - 8) for i in range(20)] +
    ["S"] + ["F %d" % i for i in range(8)] + ["S"],
    # 3) guards: W on dead rows, T on dead rows, out-of-range rowids, exhaustion
    ["N 0", "W 0 10", "F 0", "W 0 5", "T 0", "W 31 1", "N 31", "N 4", "S",
     "F 4", "F 100", "S", "T 2"],
]

reward = 0.0
try:
    # 1) single-file edit boundary --------------------------------------------------
    touched = [name for name, want in BOUNDARY.items()
               if not os.path.exists("/app/cashier/" + name) or md5("/app/cashier/" + name) != want]
    if touched:
        print("BOUNDARY VIOLATION: immutable files changed: %s" % touched)
        open("/logs/verifier/reward.txt", "w").write("0\n")
        sys.exit(0)

    rc_b, _ = run(["make", "-s", "debug", "release"], cwd="/app/cashier")
    if rc_b != 0:
        print("build failed")
        open("/logs/verifier/reward.txt", "w").write("0\n")
        sys.exit(0)

    core = 0.0
    # 2) visible case: mode parity + correctness ------------------------------------
    rc_d, out_d = run(["./build/debug/cashier", "--input", "cases.txt"],
                      cwd="/app/cashier")
    rc_r, out_r = run(["./build/release/cashier", "--input", "cases.txt"],
                      cwd="/app/cashier")
    if rc_d == 0 and rc_r == 0 and out_d == out_r:
        core += 0.25
    if rc_r == 0 and out_r == reference(open("/app/cashier/cases.txt").read()):
        core += 0.25

    # 3) hidden adversarial workloads ----------------------------------------------
    hidden_ok = 0
    for idx, ops in enumerate(HIDDEN, 1):
        path = "/tmp/hidden_%d.txt" % idx
        with open(path, "w") as f:
            f.write("\n".join(ops) + "\n")
        want = reference("\n".join(ops) + "\n")
        rc_d, out_d = run(["./build/debug/cashier", "--input", path],
                          cwd="/app/cashier")
        rc_r, out_r = run(["./build/release/cashier", "--input", path],
                          cwd="/app/cashier")
        ok = (rc_d == 0 and rc_d == rc_r and out_d == out_r and out_r == want)
        print("hidden%d ok=%s" % (idx, ok))
        if not ok:
            print("  debug rc=%d, release rc=%d" % (rc_d, rc_r))
            print("  want: %s" % want.strip().replace("\n", " | "))
            print("  got : %s" % out_r.strip().replace("\n", " | "))
        hidden_ok += 1 if ok else 0
    core += (0.35 if hidden_ok == 3 else 0.0)

    # 4) determinism: two consecutive release runs must be identical ---------------
    rc1, out1 = run(["./build/release/cashier", "--input", "cases.txt"],
                    cwd="/app/cashier")
    rc2, out2 = run(["./build/release/cashier", "--input", "cases.txt"],
                    cwd="/app/cashier")
    if rc1 == 0 and rc1 == rc2 and out1 == out2:
        core += 0.15

    # 5) isolation artifact ---------------------------------------------------------
    iso = 0.0
    if os.path.exists("/app/isolation/repro.txt") and os.path.exists("/app/isolation/notes.txt"):
        repro = open("/app/isolation/repro.txt").read()
        notes = open("/app/isolation/notes.txt").read()
        lines = [l for l in repro.splitlines() if l.strip()]
        valid_ops = all(l.split()[0] in ("N", "W", "F", "S", "T") for l in lines)
        if len(lines) >= 2 and valid_ops and ("POOLDIAG" in notes or "double" in notes.lower()):
            iso = 1.0

    reward = 0.9 * core + 0.1 * iso
    print("core=%.2f iso=%.2f reward=%.2f" % (core, iso, reward))
except Exception as e:
    print("verifier error: %r" % e)
    reward = 0.0

open("/logs/verifier/reward.txt", "w").write("%.2f\n" % reward)
PY
exit 0