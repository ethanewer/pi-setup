#!/bin/bash
# Catch-up re-runs for trials that failed for infra reasons (not scored 0 by
# legitimate agent failure). Each mini-job reruns a subset; merge with
# collect_run.py (main job first = lower priority, catch-up overrides).
set -uo pipefail

HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
SETDIR=/home/ee/general-eval-runs/catchup-tasks
export PYTHONPATH=$EVAL/agents
cd "$EVAL"

mkset() { # mkset <name> task...
  local dir="$SETDIR/$1"; shift
  mkdir -p "$dir"
  for t in "$@"; do ln -sfn "$EVAL/tasks/$t" "$dir/$t"; done
}

run_catchup() { # run_catchup <jobname> <set> [extra harbor args...]
  local name=$1 set=$2; shift 2
  echo "[catchup] $(date -Is) START $name ($(ls "$SETDIR/$set" | wc -l) tasks)"
  "$HARBOR" run -p "$SETDIR/$set" -n 8 -k 1 -y -q \
    --job-name "$name" -o "$JOBS" "$@" > "$JOBS/$name.harness.log" 2>&1
  echo "[catchup] $(date -Is) DONE $name rc=$?"
}

# pi (p setup) — v1-item-052-main fixed via p_agent.py parents[3]
mkset pi-glm cobalt-quill flint-fathom larch-hearth quartz-wharf v1-item-052-main zephyr-summit
mkset pi-dsk v1-item-052-main
run_catchup catchup-pi-glm pi-glm -a p_agent:PAgent -m openrouter/z-ai/glm-5.3-flash
run_catchup catchup-pi-dsk pi-dsk -a p_agent:PAgent -m openrouter/deepseek/deepseek-v4-flash-0731

# terminus-2 — tmux-session drops
mkset term-glm calm-canyon hollow-atlas kite-yonder onyx-ember
mkset term-dsk kite-anchor larch-ember
run_catchup catchup-terminus-glm term-glm -a terminus-2 -m openrouter/z-ai/glm-5.3-flash
run_catchup catchup-terminus-dsk term-dsk -a terminus-2 -m openrouter/deepseek/deepseek-v4-flash-0731

echo "[catchup] ALL CATCH-UPS DONE"
