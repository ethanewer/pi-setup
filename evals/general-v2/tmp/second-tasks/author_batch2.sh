#!/bin/bash
# author_batch.sh <batch-file> — author up to 4 second-coverage tasks in one session.
set -u
BATCH_FILE="$1"
ROOT=/Users/ethanewer/pi-setup/evals/general-v2
MODEL=openrouter/z-ai/glm-5.3-flash
BN=$(basename "$BATCH_FILE" .json)
OUT="$ROOT/tmp/second-tasks/b2-$BN"
mkdir -p "$OUT"
BATCH_JSON=$(cat "$BATCH_FILE")

cd "$ROOT"
p -p --no-session --model "$MODEL" "You are authoring NEW tasks for the general-v2 clean-room benchmark at $ROOT. Work through EACH competency below, one at a time.

COMPETENCIES (each needs a second independent covering task):
$BATCH_JSON

FOR EACH competency, do:
STEP 1 — Read the exemplar $ROOT/tasks/black-ink/ (task.toml, instruction.md, environment/Dockerfile, solution/, tests/test.sh, tests/hidden/, difficulty.json) to learn the contract. If this is your first task this session also read $ROOT/tools/lint_tasks.py (skim the checks) and the existing covering task named in the competency's existing_task field (read its instruction.md) — your task MUST differ in scenario, fixture values, and surface details while exercising the same competency.

STEP 2 — Author $ROOT/tasks/<id>/ with an opaque two-word id NOT already present (ls $ROOT/tasks/ to check). Required files:
- task.toml: schema_version = \"1.4\"; [metadata] difficulty (>= the competency's min_difficulty), category, verifier_kind = \"executes-deliverable\" (preferred) or \"answer-with-hidden-cases\", deliverables, tags (MUST include the competency id, e.g. \"C-xxxx\")
- instruction.md: self-contained; exact paths, formats, edge cases; no mention of Terminal-Bench
- environment/Dockerfile: FROM bench-base:python-3.12; deterministic; if you COPY files/ then create environment/files/ (add .gitkeep if empty)
- solution/solve.sh (+helpers): oracle solving from a pristine container
- tests/test.sh: verifier EXECUTING the deliverable on the hidden cases; writes /logs/verifier/reward.txt (1.0 or 0.0); must never crash on malformed/missing agent output (guard every parse)
- tests/hidden/: at least 2 hidden generalization cases with distinct inputs
- difficulty.json: same rubric shape as the exemplar

STEP 3 — Verify THIS task before moving on:
  cd $ROOT && python3 tools/lint_tasks.py 2>&1 | tail -5   # fix until 0 problems for your task
  cd $ROOT && harbor run -p tasks/<id> -a oracle -n 1 -k 1 -y -o /tmp/genv2-ab-$BN-<id> --job-name ab-$BN-<id>
  Oracle must score reward=1.0 (check /tmp/genv2-ab-$BN-<id>/**/verifier/reward.txt). If it fails, read the verifier/agent logs, fix, re-run — up to 3 attempts. If it still fails after 3 attempts, note the failure reason and move to the next competency.

CONSTRAINTS: deterministic (no network at run/verify time, fixed seeds); keep verifier runtimes modest (each run() timeout <= 300s unless the competency genuinely needs more); do not modify any existing task or shared tool.

STEP 4 — After ALL competencies in the batch are attempted, print as your FINAL lines, one per competency:
RESULT {\"cid\":\"<competency id>\",\"task_id\":\"<id>\",\"lint\":true,\"oracle_reward\":1.0}
(or lint:false / oracle_reward:0.0 / \"error\":\"<reason>\" on failure)" > "$OUT/agent.out" 2>"$OUT/agent.err"
echo "BATCH_DONE $BN rc=$?"
