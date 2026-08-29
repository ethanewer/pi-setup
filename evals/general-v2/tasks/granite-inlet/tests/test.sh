#!/bin/bash
# granite-inlet verifier (runs as root after the agent finishes; /tests read-only).
set -uo pipefail
PY="$(command -v python3)"
reward=1
mkdir -p /logs/verifier
SRV=""
# Crash-proof: always persist the reward how the run ends.
trap 'if [ -n "${SRV:-}" ]; then kill "$SRV" 2>/dev/null || true; fi; echo "${reward:-0}" > /logs/verifier/reward.txt' EXIT

# Independent argmax-mean org/model computation for an HTML leaderboard page.
compute_top() { # $1 = path to an html file
  "$PY" - "$1" <<'PY'
import re, sys
html = open(sys.argv[1]).read()
rows = re.findall(r'<tr[^>]*>(.*?)</tr>', html, re.S | re.I)
best = None
bestmean = None
for row in rows:
    cells = [re.sub(r'<[^>]*>', '', c).strip()
             for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.S | re.I)]
    if len(cells) < 2:
        continue
    name = cells[0]
    if name.lower() in ('organization', 'org/model', ''):
        continue
    nums = []
    for c in cells[1:]:
        try:
            nums.append(float(c))
        except ValueError:
            pass
    if not nums:
        continue
    mean = sum(nums) / len(nums)
    if best is None or mean > bestmean or (mean == bestmean and name < best):
        best, bestmean = name, mean
print(best)
PY
}

# 0) Visible leaderboard deliverable (before hidden re-runs overwrite it).
#    Contract is the file /app/leaderboard_top.txt (one trimmed line); the
#    fetcher script's stdout is not part of the contract.
VIS_EXP="$(compute_top /app/board/www/index.html)"
VIS="$(cat /app/leaderboard_top.txt 2>/dev/null || true)"
if [ -z "$VIS" ] || [ "$VIS" != "$VIS_EXP" ]; then
  echo "VERIFIER: visible leaderboard_top.txt='$VIS' expected='$VIS_EXP'" >&2
  reward=0
fi

# 1) Re-run the delivered evaluation driver on every fresh (hidden) dataset.
#    This must succeed and produce canonical per-task JSON under /app/results.
for h in h1 h2 h3 h4 h5; do
  if ! bash /app/run_eval.sh classify /app/tasks.yaml \
        "/tests/hidden/$h/docs.jsonl" "/tests/hidden/$h/labels.json" \
        "/app/results/_verify$h.json" >/dev/null 2>&1; then
    echo "VERIFIER: run_eval classify $h failed" >&2
    reward=0
  fi
done
for h in h6 h7; do
  if ! bash /app/run_eval.sh retrieval /app/tasks.yaml \
        "/tests/hidden/$h/queries.jsonl" "/app/results/_verify_ret$h.json" >/dev/null 2>&1; then
    echo "VERIFIER: run_eval retrieval $h failed" >&2
    reward=0
  fi
done

# 2) Hidden leaderboard: serve a fresh table, run the agent's runtime fetcher
#    over HTTP (ignoring its stdout, which is not graded), then compare the
#    delivered file to the argmax recomputed independently here.
PORT=8893
python3 -m http.server "$PORT" --directory /tests/hidden/board >/dev/null 2>&1 &
SRV=$!
sleep 1
URL="http://127.0.0.1:$PORT/table.html"
python3 /app/fetch_leaderboard.py "$URL" >/dev/null 2>&1 || true
kill "$SRV" 2>/dev/null || true
SRV=""
GOT="$(cat /app/leaderboard_top.txt 2>/dev/null || true)"
EXP="$(compute_top /tests/hidden/board/table.html)"
if [ -z "$GOT" ] || [ -z "$EXP" ] || [ "$GOT" != "$EXP" ]; then
  echo "VERIFIER: leaderboard mismatch got='$GOT' exp='$EXP'" >&2
  reward=0
fi

# 3) Deep independent verification (recomputes every metric from the fixtures).
if ! "$PY" /tests/verify.py; then
  reward=0
fi

echo "granite-inlet reward=$reward"
