#!/usr/bin/env bash
set -euo pipefail

cat > /app/validate_dates.py <<'PY_END'
import sys

def is_leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)

def is_valid(y, m, d):
    if not (1 <= y <= 9999 and 1 <= m <= 12 and 1 <= d <= 31):
        return False
    dim = [31, 29 if is_leap(y) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return d <= dim[m - 1]

with open("/app/dates.tsv") as fh:
    lines = [ln.strip() for ln in fh if ln.strip()]

out = []
for ln in lines:
    y, m, d = (int(x) for x in ln.split("-"))
    out.append("VALID" if is_valid(y, m, d) else "INVALID")

with open("/app/dates_verified.txt", "w") as fh:
    fh.write("\n".join(out) + "\n")
PY_END

python3 /app/validate_dates.py

python3 - <<'PY_END'
expected = {
    "2024-02-29": True, "1900-02-29": False, "2000-02-29": True,
    "2024-04-31": False, "2024-12-31": True,
}
rows = [ln.strip() for ln in open("/app/dates.tsv") if ln.strip()]
got = [ln.strip() for ln in open("/app/dates_verified.txt") if ln.strip()]
assert len(got) == len(rows)
for line, verdict in zip(rows, got):
    if line in expected:
        assert (verdict == "VALID") == expected[line], line
PY_END