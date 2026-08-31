#!/bin/bash
# Oracle for amber-quarry: write the triage program, then RUN it on the shipped
# visible transcripts to produce /app/verdicts_report.txt. Never reads /tests.
set -eu

cat > /app/verdict_scan.py <<'PY'
#!/usr/bin/env python3
"""Classify Amber Quarry solver transcripts as SAT / UNSAT / NOVERDICT."""
import os
import sys

SAT_VALUES = {"sat", "satisfiable"}
UNSAT_VALUES = {"unsat", "unsatisfiable", "no solution", "infeasible"}
STRIP_LEAD = " \t=:"
STRIP_TRAIL = "!.: \t"


def verdict_token(text):
    """Return 'SAT' | 'UNSAT' | 'NOVERDICT' for one transcript's full text."""
    token = None
    for raw in text.splitlines():
        line = raw.strip().lower()
        if not line.startswith("verdict"):
            continue
        value = line[len("verdict"):].lstrip(STRIP_LEAD).rstrip(STRIP_TRAIL)
        value = value.strip()
        if value in SAT_VALUES:
            token = "SAT"
        elif value in UNSAT_VALUES:
            token = "UNSAT"
        else:
            token = "NOVERDICT"
    return token if token is not None else "NOVERDICT"


def main():
    log_dir, out_path = sys.argv[1], sys.argv[2]
    names = sorted(
        n for n in os.listdir(log_dir)
        if n.endswith(".log") and os.path.isfile(os.path.join(log_dir, n))
    )
    lines = []
    for n in names:
        with open(os.path.join(log_dir, n), "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        lines.append("%s:%s" % (n, verdict_token(text)))
    with open(out_path, "w", encoding="utf-8") as fh:
        for ln in lines:
            fh.write(ln + "\n")
    print("wrote", out_path)


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/verdict_scan.py

python3 /app/verdict_scan.py /app/case/logs /app/verdicts_report.txt

echo "solve.sh done"
ls -l /app/verdict_scan.py /app/verdicts_report.txt
cat /app/verdicts_report.txt
