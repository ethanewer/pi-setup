#!/usr/bin/env bash
# hollow-fathom oracle: build all deliverables and derive the default payload.
set -euo pipefail
cd /app

# 1. derive.py
cat > /app/derive.py <<'PY'
#!/usr/bin/env python3
import sys, os, glob

def derive(cluedir):
    base = None
    with open(os.path.join(cluedir, "base.txt")) as f:
        for ln in f:
            s = ln.strip()
            if s:
                base = int(s)
                break
    if base is None:
        raise SystemExit("no base value found")
    val = base
    for p in sorted(glob.glob(os.path.join(cluedir, "step_*"))):
        try:
            with open(p) as f:
                lines = [l.strip() for l in f if l.strip() != ""]
            if len(lines) < 2:
                continue
            op = lines[0].lower()
            operand = int(lines[1])
            if op == "add":
                val += operand
            elif op == "sub":
                val -= operand
            elif op == "mul":
                val *= operand
            elif op == "div":
                val //= operand
            elif op == "mod":
                val %= operand
            else:
                continue
        except Exception:
            continue
    return val

def main():
    cluedir = sys.argv[1]
    outfile = sys.argv[2] if len(sys.argv) > 2 else "/app/answer.txt"
    payload = str(derive(cluedir))
    if outfile != "-":
        d = os.path.dirname(outfile)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(outfile, "w") as f:
            f.write(payload + "\n")
    print(payload)

if __name__ == "__main__":
    main()
PY

# 2. diff_series.py
cat > /app/diff_series.py <<'PY'
#!/usr/bin/env python3
import sys

def read_series(path):
    d = {}
    with open(path) as f:
        for ln in f:
            line = ln.strip()
            if not line:
                continue
            parts = [x.strip() for x in line.split(",")]
            if len(parts) < 2:
                continue
            if parts[0] == "key":
                continue
            try:
                v = int(parts[1])
            except ValueError:
                continue
            d[parts[0]] = v
    return d

def main():
    a = sys.argv[1]
    b = sys.argv[2]
    outfile = sys.argv[3] if len(sys.argv) > 3 else None
    da = read_series(a)
    db = read_series(b)
    diffs = [da[k] - db[k] for k in da if k in db]
    n = len(diffs)
    mean = round(sum(diffs) / n, 4) if n else 0.0
    text = str(mean)
    if outfile and outfile != "-":
        with open(outfile, "w") as f:
            f.write(text + "\n")
    print(text)

if __name__ == "__main__":
    main()
PY

# 3. report.jq and report_args.json
cat > /app/report.jq <<'JQ'
def zone_rank: if .zone == "alpha" then 0 elif .zone == "beta" then 1 elif .zone == "gamma" then 2 else 3 end;
  [ .[] |
      select((.id      | type) == "string")
    | select((.zone    | type) == "string")
    | select((.prio    | type) == "number")
    | select((.score   | type) == "number")
    | select(.prio >= 0)
  ]
| sort_by([zone_rank, .prio, .score, .id])
| .[] | "\(.id)|\(.zone)|\(.prio)|\(.score)"
JQ

cat > /app/report_args.json <<'JSON'
{
  "program": "/app/report.jq",
  "options": ["-r"]
}
JSON

# produce the default payload from the default clue set
python3 /app/derive.py /app/clues /app/answer.txt

echo "oracle done"
ls -l /app/derive.py /app/answer.txt /app/diff_series.py /app/report.jq /app/report_args.json
cat /app/diff_series.py >/dev/null