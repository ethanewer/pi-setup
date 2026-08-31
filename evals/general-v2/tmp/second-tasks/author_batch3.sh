#!/bin/bash
# author_batch3.sh <batch-file> — 1-2 competencies, with retry on silent death.
set -u
BATCH_FILE="$1"
ROOT=/Users/ethanewer/pi-setup/evals/general-v2
MODEL=openrouter/z-ai/glm-5.3-flash
BN=$(basename "$BATCH_FILE" .json)
OUT="$ROOT/tmp/second-tasks/b3-$BN"
mkdir -p "$OUT"
BATCH_JSON=$(cat "$BATCH_FILE")

cd "$ROOT"
for attempt in 1 2 3; do
  p -p --no-session --model "$MODEL" "You are authoring NEW tasks for the general-v2 clean-room benchmark at $ROOT.

COMPETENCIES (each needs a second independent covering task):
$BATCH_JSON

FOR EACH competency:
1. Read exemplar $ROOT/tasks/black-ink/ (all files) to learn the contract. If first task this session, also skim $ROOT/tools/lint_tasks.py and read the instruction.md of the competency's existing_task to ensure yours differs in scenario/details.
2. Author $ROOT/tasks/<id>/ (opaque two-word id, check it doesn't exist). Include: task.toml (schema_version=1.4, difficulty >= competency min, verifier_kind=executes-deliverable, deliverables, tags including the competency id), instruction.md (self-contained), environment/Dockerfile (FROM bench-base:python-3.12, deterministic, create files/.gitkeep if empty), solution/solve.sh (oracle), tests/test.sh (executes deliverable on hidden cases, writes /logs/verifier/reward.txt, guards all parses), tests/hidden/ (>=2 cases), difficulty.json.
3. Verify: cd $ROOT && python3 tools/lint_tasks.py 2>&1 | tail -3 (fix until clean), then harbor run -p tasks/<id> -a oracle -n 1 -k 1 -y -o /tmp/genv2-b3-$BN-<id> --job-name b3-$BN-<id> and confirm reward=1.0 in /tmp/genv2-b3-$BN-<id>/**/verifier/reward.txt. Debug+fix up to 3 attempts.
4. Print as FINAL lines, one per competency:
RESULT {\"cid\":\"<cid>\",\"task_id\":\"<id>\",\"lint\":true,\"oracle_reward\":1.0}

Constraints: deterministic, no network at run/verify, verifier timeouts <=300s, don't modify existing tasks." > "$OUT/agent.out" 2>"$OUT/agent.err"
  rc=$?
  # success if any RESULT line appeared
  if grep -q "^RESULT" "$OUT/agent.out" 2>/dev/null; then
    echo "BATCH_DONE $BN attempt=$attempt rc=$rc"
    exit 0
  fi
  echo "RETRY $BN attempt=$attempt rc=$rc out=$(wc -c < $OUT/agent.out)B"
  sleep 30
done
echo "BATCH_FAILED $BN"
