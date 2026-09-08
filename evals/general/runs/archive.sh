#!/bin/bash
# Archive every harbor job dir: live backup copy + compressed tarballs +
# merged per-task record layout (collect_run.py) + run metadata.
set -euo pipefail
JOBS=/home/ee/general-eval-runs/jobs
ARCH=/home/ee/general-eval-runs/archive
BACKUP=/home/ee/general-eval-runs/backup
EVAL=/home/ee/pi-setup/evals/general
mkdir -p "$ARCH" "$BACKUP"

settled() {
  # job finished: no pending trials and result.json idle > 2 min.
  # (n_running_trials is unreliable: trials killed at job exit stay 'running'.)
  [ -f "$1/result.json" ] || return 1
  python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['stats']
sys.exit(0 if d.get('n_pending_trials',0)==0 else 1)
" "$1/result.json" || return 1
  [ -n "$(find "$1/result.json" -mmin +2)" ]
}

# 0) ensure readability: some agent session files arrive root-owned/0600
docker run --rm -v "$JOBS:/data" bench-base:ubuntu-24.04 chmod -R a+rX /data >/dev/null 2>&1 || true

# 1) live backup copy (idempotent)
rsync -a --ignore-existing "$JOBS/" "$BACKUP/"

# 2) compressed tarballs per job
for j in "$JOBS"/*/; do
  name=$(basename "$j")
  settled "$j" || continue
  [ -f "$ARCH/$name.tar.zst" ] && continue
  echo "[archive] compressing $name"
  tar --zstd -cf "$ARCH/$name.tar.zst" -C "$JOBS" "$name"
done

# 3) merged per-task record layout, e.g. archive/records/<job>/<task>/{agent,verifier,metadata.json}
PY=/home/ee/general-eval-runs/venv/bin/python
for j in "$JOBS"/*/; do
  name=$(basename "$j")
  settled "$j" || continue
  out="$ARCH/records/$name"
  [ -d "$out" ] && continue
  case "$name" in
    *-pi-*)      agent=pi ;;
    *-terminus-*) agent=terminus-2 ;;
    *-claude-*)  agent=claude-code ;;
    *)           agent=unknown ;;
  esac
  trial=""
  for t in "$j"/*__*/; do trial="$t"; break; done
  model=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['agent']['model_name'])" "$trial/config.json" 2>/dev/null || echo '?')
  echo "[archive] collecting $name (agent=$agent model=$model)"
  "$PY" "$EVAL/tools/collect_run.py" --agent "$agent" --model "$model" --out "$out" "$j" || echo "[archive] WARN: collect failed for $name"
done

# 4) metadata sidecar
{
  echo "date: $(date -Is)"
  echo "host: $(hostname)"
  echo "pi-setup commit: $(git -C /home/ee/pi-setup rev-parse HEAD)"
  echo "harbor: $(/home/ee/general-eval-runs/venv/bin/harbor --version 2>/dev/null)"
  echo "dataset: $EVAL (765 tasks)"
  echo "models: openrouter/z-ai/glm-5.3-flash, openrouter/deepseek/deepseek-v4-flash-0731"
} > "$ARCH/METADATA.txt"

echo "[archive] done"; ls -lh "$ARCH"
