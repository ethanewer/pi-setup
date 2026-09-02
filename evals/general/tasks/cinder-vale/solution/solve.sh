#!/bin/bash
# Oracle for cinder-vale: write the planner program, then RUN it on the visible
# basket to produce /app/plans.jsonl, /app/answer.json, /app/schedule.csv.
# Never reads /tests.
set -eu

SOLVER="/app/solve.py"

# ---- 1. Write the deliverable program (this IS the work, not canned answers).
cat > "$SOLVER" <<'PY'
import csv, json, os, sys


def load_rows(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            rows.append({
                "id": r["id"],
                "batch": r["batch"],
                "volume": float(r["volume_cm3"]),
                "layers": int(r["layers"]),
                "duration": int(r["duration"]),
                "deadline": int(r["deadline"]),
                "profit": int(r["profit"]),
            })
    return rows


def solve_rows(rows):
    n = len(rows)
    order = sorted(range(n), key=lambda i: (rows[i]["deadline"], i))
    T = max((r["deadline"] for r in rows), default=0)
    NEG = -1
    # dp[t] = (best profit, best code) over selections of the processed
    # prefix whose durations sum to EXACTLY t.  code: bit (n-1-i) set when
    # row i is selected; smaller code == prefers not admitting earlier rows.
    dp = [(0, 0)] + [(NEG, 0)] * T
    for i in order:
        r = rows[i]
        bit = 1 << (n - 1 - i)
        ndp = list(dp)  # skipping row i keeps the previous state
        for t in range(r["duration"], min(r["deadline"], T) + 1):
            p, c = dp[t - r["duration"]]
            if p < 0:
                continue
            p2, c2 = p + r["profit"], c | bit
            cur = ndp[t]
            if p2 > cur[0] or (p2 == cur[0] and c2 < cur[1]):
                ndp[t] = (p2, c2)
        dp = ndp
    best_p, best_c = 0, None
    for t in range(T + 1):
        p, c = dp[t]
        if p < 0:
            continue
        if p > best_p or (p == best_p and (best_c is None or c < best_c)):
            best_p, best_c = p, c
    assert best_c is not None
    selected = sorted(i for i in range(n) if best_c & (1 << (n - 1 - i)))
    sched = sorted(selected, key=lambda i: (rows[i]["deadline"], i))
    finish, out = 0, []
    for i in sched:
        finish += rows[i]["duration"]
        out.append((rows[i]["id"], finish))
    return best_p, out


def emit(workdir, rows):
    lines = []
    for r in rows:
        rec = {"id": r["id"], "batch": r["batch"],
               "shape": {"volume_cm3": r["volume"], "layers": r["layers"],
                          "duration": r["duration"]}}
        lines.append(json.dumps(rec, separators=(",", ":")))
    with open(os.path.join(workdir, "plans.jsonl"), "w", encoding="utf-8") as fh:
        fh.write("".join(l + "\n" for l in lines))

    best_p, sched = solve_rows(rows)
    with open(os.path.join(workdir, "answer.json"), "w", encoding="utf-8") as fh:
        fh.write(str(best_p))
    with open(os.path.join(workdir, "schedule.csv"), "w", encoding="utf-8") as fh:
        fh.write("id,finish\n")
        for jid, fin in sched:
            fh.write("%s,%d\n" % (jid, fin))


def main():
    workdir = sys.argv[1] if len(sys.argv) > 1 else "/app"
    emit(workdir, load_rows(os.path.join(workdir, "input", "jobs.csv")))


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible basket (0-argument form).
python3 "$SOLVER"

echo "solve.sh done -> $SOLVER and emitted artifacts"
ls -l /app/solve.py /app/plans.jsonl /app/answer.json /app/schedule.csv
