#!/bin/bash
# Inventory pre-review: fan out competency batches to p sessions (glm-5.3-flash).
set -u
cd /Users/ethanewer/pi-setup/evals/general-v2
OUT=/Users/ethanewer/pi-setup/evals/general-v2/tmp/inv-review
MODEL=openrouter/z-ai/glm-5.3-flash
CONC=5

run_batch() {
  local i=$1
  local data
  data=$(cat /tmp/comp_prompts/batch_$i.txt)
  p -p --no-session --model "$MODEL" "You are auditing competency entries from a benchmark inventory (each: id, name, definition, failure_mode, required_artifacts, risk, min_required_difficulty). Flag ONLY real problems:
1. vague_definition: too abstract to write a concrete verifier against
2. duplicate: two entries in this batch describe essentially the same competency (give both IDs)
3. misscoped_failure_mode: wouldn't actually cause a verifier failure, or circular/trivial
4. missing_artifact: required_artifacts empty or names no concrete checkable deliverable
5. wrong_difficulty: min_required_difficulty clearly wrong for the competency
6. overlapping_scope: so broad it covers multiple unrelated skills

Be conservative; most entries are fine. Output ONLY a JSON object: {\"flags\": [{\"id\",\"issue_type\",\"explanation\",\"suggested_fix\"}], \"clean\": [ids with no issues]}

ENTRIES:
$data" > "$OUT/batch_$i.out" 2>"$OUT/batch_$i.err"
  echo "batch $i done rc=$?"
}

i=0
while [ -f /tmp/comp_prompts/batch_$i.txt ]; do
  run_batch $i &
  while [ "$(jobs -r | wc -l)" -ge $CONC ]; do wait -n; done
  i=$((i+1))
done
wait
echo "REVIEW_COMPLETE batches=$i"
