#!/bin/bash
# author_one.sh <competency-json-file> — author one second-coverage task end-to-end.
set -u
COMP_FILE="$1"
ROOT=/Users/ethanewer/pi-setup/evals/general-v2
MODEL=openrouter/z-ai/glm-5.3-flash
CID=$(python3 -c "import json;print(json.load(open('$COMP_FILE'))['id'])")
OUT="$ROOT/tmp/second-tasks/$CID"
mkdir -p "$OUT"

COMP_JSON=$(cat "$COMP_FILE")

cd "$ROOT"
p -p --no-session --model "$MODEL" "You are authoring ONE new task for the general-v2 clean-room benchmark at $ROOT.

COMPETENCY TO COVER (second independent task; do NOT copy the existing one):
$COMP_JSON

STEP 1 — Learn the contract. Read the exemplar task $ROOT/tasks/black-ink/ completely (task.toml, instruction.md, environment/Dockerfile, solution/solve.sh, tests/test.sh, difficulty.json). Also read $ROOT/tools/lint_tasks.py to know what lint enforces, and skim $ROOT/tasks/$(
python3 -c "import json;print(json.load(open('$COMP_FILE')).get('existing_task') or 'black-ink')")/instruction.md to see how the FIRST task covers this competency (your task must differ in scenario and surface details while exercising the same competency).

STEP 2 — Author a new task at $ROOT/tasks/<id>/ where <id> is an opaque two-word id (e.g. crimson-fjord) not already in $ROOT/tasks/ (check with ls). Requirements:
- task.toml: schema_version 1.4, [metadata] difficulty (at least the competency's min_required_difficulty), category, verifier_kind ('executes-deliverable' preferred), deliverables list, tags INCLUDING the competency id
- instruction.md: fully self-contained, exact paths, formats, edge cases, constraints; no reference to Terminal-Bench
- environment/Dockerfile: FROM bench-base:python-3.12; create environment/files/ (with .gitkeep if empty) if you COPY it
- solution/solve.sh (+ any solution files): oracle that solves from a pristine container
- tests/test.sh: verifier that EXECUTES the deliverable on hidden cases, writes /logs/verifier/reward.txt (1.0 pass, 0.0 fail), never crashes on malformed agent output
- tests/hidden/: at least 2 hidden generalization cases
- difficulty.json: rubric fields like the exemplar
- Deterministic: no network at verify/run time; fixed seeds

STEP 3 — Verify. Run:
  cd $ROOT && python3 tools/lint_tasks.py
until it passes your task with no errors, then:
  cd $ROOT && harbor run -p tasks/<id> -a oracle -n 1 -k 1 -y -o /tmp/genv2-author-$CID --job-name author-$CID
The oracle must score reward=1.0. If not, debug (read /tmp/genv2-author-$CID/**/verifier/test-stdout.txt and agent logs), fix, re-run. Up to 4 oracle attempts.

STEP 4 — Report. Print as your FINAL line exactly:
RESULT {\"cid\":\"$CID\",\"task_id\":\"<id>\",\"lint\":true,\"oracle_reward\":1.0}
or on failure RESULT {\"cid\":\"$CID\",\"task_id\":\"<id>\",\"lint\":false,\"oracle_reward\":0.0,\"error\":\"<short reason>\"}" > "$OUT/agent.out" 2>"$OUT/agent.err"
echo "AUTHOR_DONE $CID rc=$?"
