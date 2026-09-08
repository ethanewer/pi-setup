#!/usr/bin/env bash
# Build and publish v3.3 of the results dataset.
#
#   1. copy the downloaded v3.2 tree into a work dir
#   2. rescore every fractional reward to binary (no model involvement)
#   3. collect the 22 re-run trials into an overlay
#   4. assemble v3.3, which validates completeness + binarity and writes the
#      per-pair results.json, summary.json and the audit bundle
#   5. upload to HF
#
# Stops at the first failure. Step 4 is the gate: it exits non-zero if any pair
# is missing a task, any record is missing a file, or any reward is not 0 or 1.
set -uo pipefail

EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
SRC=/tmp/v32-full/v3.2
WORK=/tmp/v33-work/v3.2
STAGE=/tmp/v33-stage
OUT=/tmp/hf-upload/v3.3
REPO=eewer/general-agent-bench-results

set -a; . /home/ee/pi-setup/.env; set +a

step() { echo; echo "=== [$(date -Is)] $* ==="; }
die()  { echo "FATAL: $*" >&2; exit 1; }

[ -d "$SRC" ] || die "downloaded v3.2 tree missing at $SRC"

step "1/5 copy v3.2 into $WORK"
rm -rf /tmp/v33-work "$STAGE" "$OUT"
mkdir -p "$(dirname "$WORK")"
cp -a "$SRC" "$WORK"
echo "records: $(find "$WORK" -name metadata.json | wc -l)"

step "2/5 rescore fractional rewards to binary"
python3 "$EVAL/tools/rescore_binary.py" --tree "$WORK" --apply --json > /tmp/v33-rescore.json
rc=$?
# exit 1 here means some records still have no reward.txt; the overlay in step 3
# is what fills them, so it is expected at this point and step 4 is the real gate
echo "rescore rc=$rc (1 is expected until the re-runs are overlaid)"
RESCORED=$(jq -r '.totals.rescored' /tmp/v33-rescore.json)
RESCORED_TASKS=$(jq -r '.distinct_tasks_rescored | length' /tmp/v33-rescore.json)
RERUN=$(jq -r '.totals.needs_rerun' /tmp/v33-rescore.json)
BEFORE=$(jq -r '.totals.reward_before' /tmp/v33-rescore.json)
AFTER=$(jq -r '.totals.reward_after' /tmp/v33-rescore.json)
echo "rescored=$RESCORED across $RESCORED_TASKS tasks; still needing re-run=$RERUN"

step "3/5 collect the re-run trials into $STAGE"
python3 "$EVAL/tools/collect_task_records.py" \
  --jobs "$JOBS" --out "$STAGE" \
  --job v33-pi-glm:pi:z-ai/glm-5.3-flash:openrouter/z-ai/glm-5.3-flash \
  --job v33-pi-dsk:pi:deepseek/deepseek-v4-flash-0731:openrouter/deepseek/deepseek-v4-flash-0731 \
  --job v33-t2-dsk:terminus-2:deepseek/deepseek-v4-flash-0731:openrouter/deepseek/deepseek-v4-flash-0731 \
  --job v33-claude-glm:claude-code:z-ai/glm-5.3-flash:z-ai/glm-5.3-flash \
  --job v33-claude-dsk:claude-code:deepseek/deepseek-v4-flash-0731:deepseek/deepseek-v4-flash-0731 \
  || die "collect_task_records failed"
OVERLAID=$(find "$STAGE" -name metadata.json | wc -l)
echo "overlay records: $OVERLAID (must equal $RERUN)"
[ "$OVERLAID" -eq "$RERUN" ] || die "overlay has $OVERLAID records but $RERUN were unscoreable"

step "4/5 assemble and validate v3.3"
python3 "$EVAL/tools/assemble_publish.py" \
  --version v3.3 --mirror "$WORK" --overlay "$STAGE" --out "$OUT" \
  --note "v3.3 = the v3.2 tree with every reward made binary and every unscoreable record re-run. All six harness/model pairs cover all 787 suite tasks." \
  --note "45 task verifiers awarded partial credit (41 v1-item-*, 3 v1-skill-*, zephyr-bridge); all now emit 0 or 1. Each was binarized at full credit, so the new reward is 1 exactly where the old score was >= 1.0 and the pass set is unchanged. Enforced by tools/check_binary_reward.py: 787/787 BINARY." \
  --note "$RESCORED records across $RESCORED_TASKS tasks were rescored arithmetically from their published value, with no model inference. Total reward $BEFORE -> $AFTER." \
  --note "$OVERLAID records that shipped with no verifier/reward.txt were re-run with harbor 0.22.0 against the live suite, same harnesses, models and flags as the v3.1 runs." \
  --note "Carried-over records were produced by the pre-binarization verifiers. That is sound because only the reward computation changed, not the task instructions or environments, and old 1.0 maps to new 1 while old 0.0 maps to new 0." \
  --note "First version to ship per-pair results.json aggregates. v3.2 shipped none, and the v3.1 aggregate it inherited for claude-code/glm said 647.50 where the reward files sum to 648.50." \
  || die "assemble_publish refused to publish (see problems above)"

step "5/5 upload v3.3 to $REPO"
# hf upload has no retry or concurrency flag, and the Hub already 429'd the
# download of this same repo. upload_folder skips files whose hash already
# matches, so re-running the identical command resumes rather than duplicates.
nfiles=$(find "$OUT" -type f | wc -l)
echo "uploading $nfiles files"
ok=0
for attempt in 1 2 3 4 5 6; do
  echo "[upload] $(date -Is) attempt $attempt"
  if hf upload "$REPO" "$OUT" v3.3 --repo-type dataset --token "$HF_TOKEN" \
       --commit-message "v3.3: binary rewards, $OVERLAID re-run records, per-pair aggregates" \
       --commit-description "Rescores the $RESCORED published records whose verifier awarded partial credit (new reward is 1 exactly where the old score was >= 1.0) and replaces the $OVERLAID records that shipped with no verifier/reward.txt. All 45 partial-credit verifiers are now binary in the suite, enforced by tools/check_binary_reward.py. Adds the per-pair results.json and summary.json that v3.2 never shipped, plus the audit bundle." \
       > /tmp/v33-upload.log 2>&1; then
    ok=1; echo "[upload] $(date -Is) OK"; break
  fi
  echo "[upload] $(date -Is) failed, backing off $((attempt * 60))s"
  tail -5 /tmp/v33-upload.log
  sleep $((attempt * 60))
done
[ "$ok" -eq 1 ] || die "upload failed after 6 attempts; see /tmp/v33-upload.log"

step "verify the uploaded tree against the Hub"
# Read it back through the paginated tree endpoint. Do NOT use the siblings array
# from /api/datasets/<id>: on this repo it returns 62,787 of 68,064 files and
# drops whole subtrees, which is how an earlier check here reported an entire
# harness/model pair as missing when it was present.
python3 - "$REPO" "$nfiles" <<'PY' || die "uploaded tree does not match local"
import json, os, re, sys, urllib.request
repo, expect = sys.argv[1], int(sys.argv[2])
tok = os.environ['HF_TOKEN']
NEXT = re.compile(r'<([^>]+)>;\s*rel="next"')
url = f"https://huggingface.co/api/datasets/{repo}/tree/main/v3.3?recursive=true&limit=1000"
seen, pages = 0, 0
while url:
    pages += 1
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=300) as r:
        body, link = r.read(), r.headers.get('link', '')
    seen += sum(1 for e in json.loads(body) if e['type'] == 'file')
    m = NEXT.search(link or '')
    url = m.group(1) if m else None
    if pages > 500:
        sys.exit('runaway pagination')
print(f"hub v3.3 files={seen} local={expect} pages={pages}")
sys.exit(0 if seen == expect else 1)
PY

step "done"
echo "v3.3 published: $(find "$OUT" -type f | wc -l) files, $(du -sh "$OUT" | cut -f1)"
