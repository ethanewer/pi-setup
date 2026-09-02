#!/bin/bash
# Oracle for "meadow-yonder": author four reusable data-log reporting tools and
# produce the exact reports/answers by RUNNING them. Never reads /tests.
set -euo pipefail

# ---- 1. access-log parser ---------------------------------------------------
cat > /app/logstats.py <<'PY'
#!/usr/bin/env python3
import re
import sys

CLIENT_RE = re.compile(r"^[A-Za-z0-9._:\-]+$")


def classify(line):
    s = line.strip()
    if not s or s.startswith("#"):
        return None
    tokens = s.split()
    if not tokens:
        return None
    client = tokens[0]
    if not CLIENT_RE.fullmatch(client):
        return None
    if not any(c.isdigit() for c in client):
        return None
    return client


def main():
    path = sys.argv[1]
    total = 0
    unique = set()
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            c = classify(line)
            if c is not None:
                total += 1
                unique.add(c)
    sys.stdout.write("total=%d\nunique=%d\n" % (total, len(unique)))


if __name__ == "__main__":
    main()
PY
chmod +x /app/logstats.py

# ---- 2. produce report.txt ------------------------------------------------
python3 /app/logstats.py /app/data/access.log > /app/report.txt

# ---- 3. fixed CSV normalizer ------------------------------------------------
cat > /app/fixed_script.py <<'PY'
#!/usr/bin/env python3
import sys


def process(src, dst):
    with open(src, "r", encoding="utf-8", errors="replace") as fin, \
            open(dst, "w", encoding="utf-8") as fout:
        for raw in fin:
            line = raw.strip()  # kills the trailing \n (and \r) that caused accumulation
            if not line or line.startswith("#"):
                continue
            fields = [f.strip() for f in line.split(",")]
            fout.write(",".join(fields) + "\n")


if __name__ == "__main__":
    process(sys.argv[1], sys.argv[2])
PY
chmod +x /app/fixed_script.py

# ---- 4. cluster-state sampler -----------------------------------------------
cat > /app/sample_cluster.sh <<'SH'
#!/bin/bash
# sample_cluster.sh <samples> <interval_sec> <logfile> [probe] [state_file]
set -u
samples="${1:?samples}"
interval="${2:?interval_sec}"
logfile="${3:?logfile}"
probe="${4:-/app/data/cluster_probe}"
state="${5:-/app/data/cluster_state}"

mkdir -p "$(dirname "$logfile")"
: > "$logfile"

for i in $(seq 1 "$samples"); do
  if [ -f "$probe" ]; then
    bash "$probe" "$state" || true
  fi
  total="0"
  idle="0"
  if [ -f "$state" ]; then
    total=$(sed -n 's/^[[:space:]]*total=\([0-9][0-9]*\).*/\1/p' "$state" | tail -1)
    idle=$(sed -n 's/^[[:space:]]*idle=\([0-9][0-9]*\).*/\1/p' "$state" | tail -1)
    [ -z "$total" ] && total=0
    [ -z "$idle" ] && idle=0
  fi
  total=$(printf '%d' "$total" 2>/dev/null || echo 0)
  idle=$(printf '%d' "$idle" 2>/dev/null || echo 0)
  [ "$total" -lt 0 ] && total=0
  [ "$idle" -lt 0 ] && idle=0

  if [ "$total" -gt 0 ]; then
    fraction=$(python3 -c "print('%.3f' % ($idle / $total))")
  else
    fraction="0.000"
  fi
  ts=$(date +%s)
  printf '%s,%s,%s,%s\n' "$ts" "$total" "$idle" "$fraction" >> "$logfile"

  if [ "$i" -lt "$samples" ]; then
    sleep "$interval"
  fi
done
SH
chmod +x /app/sample_cluster.sh

# ---- 5. produce /app/cluster.log -------------------------------------------
bash /app/sample_cluster.sh 5 1 /app/cluster.log

# ---- 6. exact-format answer computer ----------------------------------------
cat > /app/compute_answer.py <<'PY'
#!/usr/bin/env python3
import re
import sys


def main():
    clog, rep = sys.argv[1], sys.argv[2]
    outfile = sys.argv[3] if len(sys.argv) > 3 else None

    idle_sum = 0
    try:
        with open(clog, encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split(",")
                if len(parts) >= 3:
                    try:
                        idle_sum += int(parts[2])
                    except ValueError:
                        pass
    except OSError:
        pass

    unique = 0
    try:
        with open(rep, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"unique=(\d+)", line.strip())
                if m:
                    unique = int(m.group(1))
    except OSError:
        pass

    text = "%d\n" % (idle_sum + unique)
    sys.stdout.write(text)
    if outfile:
        with open(outfile, "w", encoding="utf-8") as f:
            f.write(text)


if __name__ == "__main__":
    main()
PY
chmod +x /app/compute_answer.py

# ---- 7. produce /app/answer.txt ---------------------------------------------
python3 /app/compute_answer.py /app/cluster.log /app/report.txt /app/answer.txt

echo "oracle complete"
cat /app/report.txt
echo "answer: $(cat /app/answer.txt)"