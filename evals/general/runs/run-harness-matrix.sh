#!/bin/bash
# General eval: harness matrix over the LIVE setup — every agent resolves its
# versions, patches, wrappers, and extensions from the host pi-setup at run
# time (agents/setup_sync.py), so updating the setup needs no eval changes.
#
#   p_agent:PAgent        p    — lean pi profile (no extensions/skills)
#   pi_agent:PiSetupAgent pi   — full pi profile + the setup's container-safe forks
#   occ_agent:OccAgent    occ  — Claude Code through the setup's occ wrapper
#   ocdx_agent:OcdxAgent  ocdx — Codex CLI through the setup's ocdx wrapper
#   terminus-2            tb2  — harbor's bundled TerminalBench 2 agent
#   claude-code           cc   — harbor's bundled Claude Code agent (reference)
#
# Usage: HARBOR=/path/to/harbor OUT=/path/to/jobs bash runs/run-harness-matrix.sh
# Optional: TASKS="task-a task-b" (default: the full tasks/ tree), MODELS, JOBS.
set -uo pipefail
cd "$(dirname "$0")/.."

HARBOR="${HARBOR:-$(command -v harbor)}"
[ -n "$HARBOR" ] || { echo "harbor not found; set HARBOR=/path/to/venv/bin/harbor" >&2; exit 2; }
OUT="${OUT:-$HOME/general-eval-runs/jobs}"
JOBS="${JOBS:-64}"
MODELS="${MODELS:-openrouter/z-ai/glm-5.3-flash}"
export PYTHONPATH="$PWD/agents"

# occ/ocdx agents resolve the key themselves via setup_sync (env -> ~/.openrouter-key
# -> pi auth); export it once so harbor's own connection plumbing sees it too.
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  OPENROUTER_API_KEY="$(pi auth print-api-key --provider openrouter 2>/dev/null || true)"
  export OPENROUTER_API_KEY
fi
mkdir -p "$OUT"

run_job() {
  local name=$1; shift
  echo "[rig] $(date -Is) START $name"
  "$HARBOR" run \
    -p tasks \
    -n "$JOBS" -k 1 -y -q \
    --job-name "$name" -o "$OUT" \
    "$@" > "$OUT/$name.harness.log" 2>&1
  echo "[rig] $(date -Is) DONE $name rc=$?"
}

for MODEL in $MODELS; do
  ms=$(echo "$MODEL" | tr '/:' '__')
  slug="${MODEL#openrouter/}"

  # pi-family agents take the provider-prefixed model path.
  run_job "general-p-${ms}"      -a p_agent:PAgent        -m "$MODEL"
  run_job "general-pi-${ms}"     -a pi_agent:PiSetupAgent -m "$MODEL"
  run_job "general-terminus-${ms}" -a terminus-2          -m "$MODEL"

  # occ/ocdx take the bare OpenRouter slug (their wrappers pin the endpoint).
  run_job "general-occ-${ms}"    -a occ_agent:OccAgent    -m "$slug"
  run_job "general-ocdx-${ms}"   -a ocdx_agent:OcdxAgent  -m "$slug"
done

echo "[rig] HARNESS MATRIX COMPLETE"
