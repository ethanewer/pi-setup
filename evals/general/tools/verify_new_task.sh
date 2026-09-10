#!/usr/bin/env bash
# Per-task acceptance gate for newly authored tasks.
#
# Proves the task in BOTH directions with harbor:
#
#   oracle  -> reward must be 1.0   (the verifier accepts a correct solution)
#   nop     -> reward must be 0.0   (the verifier rejects an untouched container)
#
# Either half alone is worthless. A verifier that unconditionally writes 1
# passes the oracle census while measuring nothing; one that unconditionally
# writes 0 passes the negative control while being unpassable. WORKFLOW.md
# documents three tasks that scored 1 under nop and 28 whose own reference
# solution could not pass, which is why this script runs both.
#
# PARALLEL SAFE. Several authors run this at once, so:
#
#   - The suite-wide static gates are run, but a gate failure is attributed to
#     this task only if the gate's own output names it. Another author's
#     half-written task must not fail your run. Those gates print only counts
#     when clean and name offenders when not, so grepping for the task id is
#     the right filter.
#   - No `docker images` before/after diff and no `docker container prune` or
#     image prune. A diff attributes one agent's new image to another and
#     deletes it; a prune can remove a stopped container another agent has not
#     finished reading. harbor removes its own trial images, and this host runs
#     other live work, so cache is handled by runs/disk-keeper-v41.sh instead.
#   - Job output goes under /tmp/v41-verify/<task>/ so runs cannot collide.
#
# Usage: bash tools/verify_new_task.sh TASK [TASK...]
# Exit 0 only if every named task passes both directions and its own static gates.
set -uo pipefail

EVAL=/home/ee/pi-setup/evals/general
export PATH=/tmp/venv-recreate/bin:$PATH
PY=python3

cd "$EVAL" || exit 2
[ "$#" -ge 1 ] || { echo "usage: verify_new_task.sh TASK [TASK...]" >&2; exit 2; }
command -v harbor >/dev/null || { echo "FATAL: harbor not on PATH" >&2; exit 2; }

rc_all=0
declare -a RESULTS=()

# Suite-wide gates. Cached across tasks in one invocation.
GATE_DIR=/tmp/v41-gates.$$
mkdir -p "$GATE_DIR"
run_gate() {  # name, command...
  local name=$1; shift
  local out="$GATE_DIR/$name.out"
  if [ ! -f "$out" ]; then
    ( "$@" >"$out" 2>&1; echo $? >"$GATE_DIR/$name.rc" )
  fi
}
echo "=== [$(date -Is)] running suite-wide static gates once ==="
run_gate lint        $PY tools/lint_tasks.py
run_gate guard       $PY tools/ensure_reward_guard.py
run_gate threads     $PY tools/pin_numeric_threads.py
run_gate gitsafe     $PY tools/ensure_git_safe_directory.py
run_gate pippins     $PY tools/pin_python_dependencies.py
run_gate difficulty  $PY tools/check_difficulty.py --allow-unmeasured
for g in lint guard threads gitsafe pippins difficulty; do
  echo "  $g: rc=$(cat "$GATE_DIR/$g.rc") $(tail -1 "$GATE_DIR/$g.out" | cut -c1-90)"
done

for t in "$@"; do
  echo
  echo "=== [$(date -Is)] $t ==="
  if [ ! -d "tasks/$t" ]; then
    echo "  FAIL: no such task directory"; rc_all=1; RESULTS+=("$t MISSING"); continue
  fi
  task_rc=0

  # --- static gates, filtered to this task ---
  for g in lint guard threads gitsafe pippins difficulty; do
    grc=$(cat "$GATE_DIR/$g.rc")
    [ "$grc" = 0 ] && continue
    mine=$(grep -E "(^|[^a-z0-9-])${t}([^a-z0-9-]|$)" "$GATE_DIR/$g.out" | head -30)
    if [ -n "$mine" ]; then
      echo "  FAIL static/$g names this task:"; echo "$mine" | sed 's/^/    | /'
      task_rc=1
    else
      echo "  note  static/$g rc=$grc but does not name $t (another task); ignored"
    fi
  done

  # --- binary reward, exact single-task mode ---
  if bout=$($PY tools/check_binary_reward.py --task "$t" 2>&1); then
    echo "  ok    binary_reward: $(echo "$bout" | tail -1 | cut -c1-90)"
  else
    echo "  FAIL binary_reward:"; echo "$bout" | tail -20 | sed 's/^/    | /'; task_rc=1
  fi

  # --- both directions under harbor ---
  for agent in oracle nop; do
    JOBS="${JOBS:-/tmp/v41-verify/$t}"
    rm -rf "$JOBS/$t-$agent"; mkdir -p "$JOBS"
    log="$JOBS/$t-$agent.log"
    timeout 3000 harbor run -p "tasks/$t" -a "$agent" -k 1 -n 1 -y -q \
      --job-name "$t-$agent" -o "$JOBS/$t-$agent" >"$log" 2>&1
    hrc=$?
    rfile=$(find "$JOBS/$t-$agent" -path "*/verifier/reward.txt" -print -quit 2>/dev/null | head -1)
    val=""; [ -n "$rfile" ] && val=$(tr -d '[:space:]' <"$rfile")
    echo "  $agent: harbor_rc=$hrc reward='${val:-<none>}'"
    want=1; [ "$agent" = nop ] && want=0
    if [ "$val" != "$want" ]; then
      if [ "$agent" = oracle ]; then
        echo "  FAIL oracle: the reference solution did not earn reward 1"
      else
        echo "  FAIL nop: an untouched container earned '${val:-<none>}' -- the verifier is vacuous"
      fi
      tail -25 "$log" | sed 's/^/    log| /'
      find "$JOBS/$t-$agent" -name "test-stdout.txt" -exec tail -40 {} \; 2>/dev/null | sed 's/^/    ver| /'
      task_rc=1
    fi
  done

  if [ "$task_rc" = 0 ]; then RESULTS+=("$t PASS")
  else rc_all=1; RESULTS+=("$t FAIL"); fi
done

rm -rf "$GATE_DIR"
echo
echo "=== summary ==="
printf '%s\n' "${RESULTS[@]}"
echo "disk free: $(df --output=avail -BG /var/lib/docker 2>/dev/null | tail -1 | tr -dc '0-9')G"
echo "=== [$(date -Is)] exit $rc_all ==="
exit $rc_all
