#!/usr/bin/env bash
# Measure ACTUAL per-container resource use during concurrent harbor trials,
# so run concurrency can be sized from observation instead of from the
# memory_mb declarations in task.toml.
#
# The declarations are hard cgroup caps (harbor's docker environment resolves
# ResourceMode.AUTO to LIMIT), not reservations, so summing them overstates what
# a run needs by an unknown factor. Only sampling live containers answers it.
#
# Uses the `oracle` agent, which applies each task's reference solution and needs
# no model or API key. Oracle is the right probe here because it does the real
# work -- it builds, runs the project's own tests and the hidden cases -- so it
# reaches the memory and CPU peaks a trial actually hits. `nop` would measure an
# idle container and understate everything.
set -uo pipefail
cd /home/ee/pi-setup/evals/general

SAMPLE=${SAMPLE:?set SAMPLE to a comma-separated task list}
N=${N:-14}
OUT=${OUT:-/tmp/conc-exp}

rm -rf "$OUT"; mkdir -p "$OUT/runset"
IFS=',' read -ra TASKS <<< "$SAMPLE"
for t in "${TASKS[@]}"; do
  [ -d "tasks/$t" ] || { echo "MISSING TASK $t"; exit 2; }
  ln -sfn "$PWD/tasks/$t" "$OUT/runset/$t"
done
echo "runset: $(ls "$OUT/runset" | wc -l) tasks, concurrency $N"

df -B1 --output=avail / | tail -1 | tr -d ' ' > "$OUT/disk_before"
docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' > "$OUT/dockerdf_before" 2>/dev/null

# Sampler: per-container cpu/mem every 8s, host memory every 8s.
(
  while true; do
    ts=$(date +%s)
    docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null \
      | awk -v ts="$ts" -F'\t' '{print ts"\t"$1"\t"$2"\t"$3"\t"$4}' >> "$OUT/stats.tsv"
    free -m | awk -v ts="$ts" 'NR==2{print ts"\t"$3"\t"$7}' >> "$OUT/host.tsv"
    sleep 8
  done
) &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT

PATH=/tmp/venv-recreate/bin:$PATH timeout 5400 harbor run \
  -p "$OUT/runset" -a oracle -k 1 -n "$N" -y -q \
  --job-name conc-exp -o "$OUT/job" > "$OUT/harbor.log" 2>&1
echo "HARBOR_EXIT=$?" | tee -a "$OUT/harbor.log"

kill $SAMPLER 2>/dev/null
df -B1 --output=avail / | tail -1 | tr -d ' ' > "$OUT/disk_after"
docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' > "$OUT/dockerdf_after" 2>/dev/null
echo "SAMPLE_COMPLETE"
