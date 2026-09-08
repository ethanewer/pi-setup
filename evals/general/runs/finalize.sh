#!/bin/bash
# Final merge: per (harness, model), merge main job + catch-up job via
# collect_run.py (catch-up = higher priority), then report reward/765.
set -uo pipefail
PY=/home/ee/general-eval-runs/venv/bin/python
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
FINAL=/home/ee/general-eval-runs/final
mkdir -p "$FINAL"

merge() { # merge <label> <agent> <model> <main-job> [extra-root...]
  local label=$1 agent=$2 model=$3 main=$4; shift 4
  local out="$FINAL/$label"
  local roots=("$JOBS/$main")
  for e in "$@"; do roots+=("$JOBS/$e"); done
  rm -rf "$out"
  "$PY" "$EVAL/tools/collect_run.py" --agent "$agent" --model "$model" \
      --out "$out" "${roots[@]}" | tail -2
}

merge pi-glm       pi          openrouter/z-ai/glm-5.3-flash                 general-pi-glm       catchup-pi-glm-v1 catchup-pi-glm-v2
merge pi-dsk       pi          openrouter/deepseek/deepseek-v4-flash-0731    general-pi-dsk       catchup-pi-dsk-v1 catchup-pi-dsk-v2
merge terminus-glm terminus-2  openrouter/z-ai/glm-5.3-flash                 general-terminus-glm catchup-terminus-glm
merge terminus-dsk terminus-2  openrouter/deepseek/deepseek-v4-flash-0731    general-terminus-dsk catchup-terminus-dsk
merge claude-glm   claude-code z-ai/glm-5.3-flash                            general-claude-glm
merge claude-dsk   claude-code deepseek/deepseek-v4-flash-0731               general-claude-dsk

echo
echo "=== FINAL RESULTS (reward / 765 tasks) ==="
python3 - "$FINAL" <<'EOF'
import json, sys
from pathlib import Path
final = Path(sys.argv[1])
rows = []
for d in sorted(final.iterdir()):
    if not d.is_dir(): continue
    # collect_run layout: OUT/<agent>/<task>/
    task_dirs = [t for sub in d.iterdir() if sub.is_dir() for t in sub.iterdir() if t.is_dir()]
    total, n = 0.0, 0
    missing = []
    for t in sorted(task_dirs):
        md = t / "metadata.json"
        if not md.exists():
            missing.append(t.name); continue
        m = json.loads(md.read_text())
        r = m.get("reward")
        if r is None: missing.append(t.name); continue
        total += float(r); n += 1
    rows.append((d.name, total, n, missing))
print(f"{'run':<15} {'reward':>8} {'scored':>7} {'rate':>7}  missing")
for name, total, n, missing in rows:
    miss = ",".join(missing) if missing else "-"
    print(f"{name:<15} {total:>8.2f} {n:>7} {total/765:>7.3f}  {miss}")
EOF
