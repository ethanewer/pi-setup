#!/usr/bin/env bash
# Publish a new version of the run-record dataset.
#
# Chains the three tools that already exist into the order they must run in, and
# stops at the first failure:
#
#   1. rescore_binary.py    fractional published rewards -> binary, no inference
#   2. collect_task_records.py  harbor trials -> an overlay in the published layout
#   3. assemble_publish.py  carry forward + overlay + validate + write aggregates
#   4. hf upload            publish, then read the tree back and compare counts
#
# Step 3 is the gate. It exits non-zero unless every harness/model pair covers
# every suite task, every record has all four files, and every reward is exactly
# 0 or 1, so a partial rollout cannot reach the Hub.
#
# Step 4 reads the tree back through the paginated /tree endpoint. Do not use the
# siblings array from /api/datasets/<id>: on this repo it returns 62,787 of
# 68,064 files and drops whole subtrees silently, which once made an entire
# harness/model pair look missing when it was present.
#
# Usage:
#   tools/publish_version.sh --version v3.3 --mirror DIR --out DIR \
#       [--overlay DIR]... [--job SPEC]... [--repo OWNER/NAME] [--extra PATH]...
#       [--no-upload]
#
#   --job SPEC   jobname:harness:model-in-path:model-in-metadata, passed through
#                to collect_task_records.py. Omit --job entirely to skip
#                collection and publish the mirror plus overlays as they stand.
#   --extra PATH copy a derived file into the published tree root before
#                uploading, for artifacts computed from the run records rather
#                than from specs/, so they are not part of the audit bundle.
#   --require-rerun TASK
#                assert that every pair in the mirror has a freshly collected
#                record for TASK in the overlay, and die if any pair would fall
#                back to the mirror's copy. Repeatable.
#
# Requires HF_TOKEN in the environment for --no-upload=false.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
REPO=eewer/general-agent-bench-results
VERSION="" MIRROR="" OUT="" NO_UPLOAD=0
OVERLAYS=() JOBS=() JOBS_DIR="" STAGE="" EXTRAS=()
NOTES=() REQUIRE_RERUN=()

die() { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "=== [$(date -Is)] $* ==="; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION=$2; shift 2 ;;
    --mirror)    MIRROR=$2; shift 2 ;;
    --out)       OUT=$2; shift 2 ;;
    --overlay)   OVERLAYS+=("$2"); shift 2 ;;
    --job)       JOBS+=("$2"); shift 2 ;;
    --jobs-dir)  JOBS_DIR=$2; shift 2 ;;
    --stage)     STAGE=$2; shift 2 ;;
    --repo)      REPO=$2; shift 2 ;;
    --note)      NOTES+=("$2"); shift 2 ;;
    --extra)     EXTRAS+=("$2"); shift 2 ;;
    --require-rerun) REQUIRE_RERUN+=("$2"); shift 2 ;;
    --no-upload) NO_UPLOAD=1; shift ;;
    *)           die "unknown argument: $1" ;;
  esac
done

[ -n "$VERSION" ] || die "--version is required"
[ -n "$MIRROR" ]  || die "--mirror is required"
[ -n "$OUT" ]     || die "--out is required"
[ -d "$MIRROR" ]  || die "mirror tree missing: $MIRROR"
command -v python3 >/dev/null || die "python3 not found"

# ---------------------------------------------------------------- 1. rescore
step "1/4 rescore fractional rewards in a working copy of the mirror"
WORK="$(dirname "$OUT")/.publish-work-$(basename "$MIRROR")"
rm -rf "$WORK"; mkdir -p "$(dirname "$WORK")"
cp -a "$MIRROR" "$WORK"
echo "records: $(find "$WORK" -name metadata.json | wc -l)"
python3 "$HERE/rescore_binary.py" --tree "$WORK" --apply --json > /tmp/rescore-$VERSION.json
rc=$?
# exit 1 means records still have no reward.txt. An overlay fills those, so it is
# expected here; step 3 is the gate that decides.
RESCORED=$(python3 -c "import json;print(json.load(open('/tmp/rescore-$VERSION.json'))['totals']['rescored'])")
RERUN=$(python3 -c "import json;print(json.load(open('/tmp/rescore-$VERSION.json'))['totals']['needs_rerun'])")
echo "rescore rc=$rc rescored=$RESCORED still_unscoreable=$RERUN"

# ---------------------------------------------------------------- 2. collect
OVERLAY_ARGS=()
for o in ${OVERLAYS[@]+"${OVERLAYS[@]}"}; do
  [ -n "$o" ] && OVERLAY_ARGS+=(--overlay "$o")
done
if [ ${#JOBS[@]} -gt 0 ]; then
  step "2/4 collect harbor trials into an overlay"
  STAGE="${STAGE:-/tmp/publish-stage-$VERSION}"
  rm -rf "$STAGE"
  COLLECT=(--out "$STAGE")
  [ -n "$JOBS_DIR" ] && COLLECT+=(--jobs "$JOBS_DIR")
  for j in "${JOBS[@]}"; do COLLECT+=(--job "$j"); done
  python3 "$HERE/collect_task_records.py" "${COLLECT[@]}" || die "collect_task_records failed"
  got=$(find "$STAGE" -name metadata.json | wc -l)
  echo "overlay records: $got (records needing a re-run in the mirror: $RERUN)"
  # The overlay must COVER every unscoreable record, but it may legitimately be
  # larger: a task whose verifier or environment was repaired has to be re-run
  # for every pair even though its old records were scoreable. Requiring equality
  # would reject exactly the case that most needs republishing.
  RESCORE_JSON=/tmp/rescore-$VERSION.json STAGE="$STAGE" python3 - <<'PY' || die "overlay does not cover every record that needed a re-run"
import json, os, sys
from pathlib import Path
data = json.load(open(os.environ['RESCORE_JSON']))
stage = Path(os.environ['STAGE'])
have = set()
for meta in stage.rglob('metadata.json'):
    rel = meta.parent.relative_to(stage).parts
    if len(rel) == 4:
        have.add(('/'.join(rel[:3]), rel[3]))
missing = []
for pair, stats in data['pairs'].items():
    for task in stats['rerun_tasks']:
        if (pair, task) not in have:
            missing.append(f'{pair}/{task}')
print(f'overlay covers {len(have)} (pair, task) records; '
      f'uncovered that needed a re-run: {len(missing)}')
for m in missing[:20]:
    print('  MISSING', m)
sys.exit(1 if missing else 0)
PY
  # A repaired task has to be re-run for every pair, but its old records are
  # scoreable, so nothing else in this pipeline notices when one is missing from
  # the overlay: assemble_publish just carries the mirror's stale record forward
  # and the tree still validates as complete and binary. v3.4 shipped two such
  # records for terminus-2/glm because the retry job was left out of the --job
  # list, and one of them published a 0 where the re-run had earned a 1.
  if [ ${#REQUIRE_RERUN[@]} -gt 0 ]; then
    STAGE="$STAGE" MIRROR="$MIRROR" python3 - "${REQUIRE_RERUN[@]}" <<'PY' || die "a task that had to be re-run is missing from the overlay for some pair"
import os, sys
from pathlib import Path
stage = Path(os.environ['STAGE'])
mirror = Path(os.environ['MIRROR'])
tasks = sys.argv[1:]

def pairs_with_task(root, task):
    out = set()
    if not root.is_dir():
        return out
    for p in root.glob(f'*/*/*/{task}'):
        if p.is_dir():
            out.add('/'.join(p.relative_to(root).parts[:3]))
    return out

mirror_pairs = {'/'.join(p.relative_to(mirror).parts[:3])
                for p in mirror.glob('*/*/*/') if p.is_dir()}
missing = []
for task in tasks:
    have = pairs_with_task(stage, task)
    for pair in sorted(mirror_pairs):
        if pair not in have:
            missing.append(f'{pair}/{task}')
print(f'required re-runs: {len(tasks)} tasks x {len(mirror_pairs)} pairs'
      f' = {len(tasks) * len(mirror_pairs)} records; absent from the overlay:'
      f' {len(missing)}')
for m in missing[:20]:
    print('  NOT RE-RUN', m)
if missing:
    print('These would silently fall back to the mirror\'s pre-repair record.',
          file=sys.stderr)
sys.exit(1 if missing else 0)
PY
  fi
  OVERLAY_ARGS+=(--overlay "$STAGE")
else
  step "2/4 no --job given; skipping collection"
fi

# ---------------------------------------------------------------- 3. assemble
step "3/4 assemble and validate $VERSION"
ASM=(--version "$VERSION" --mirror "$WORK" --out "$OUT" ${OVERLAY_ARGS[@]+"${OVERLAY_ARGS[@]}"})
for n in ${NOTES[@]+"${NOTES[@]}"}; do [ -n "$n" ] && ASM+=(--note "$n"); done
python3 "$HERE/assemble_publish.py" "${ASM[@]}" || die "assemble_publish refused to publish"

for e in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
  [ -f "$e" ] || die "--extra file missing: $e"
  cp "$e" "$OUT/$(basename "$e")"
  echo "staged extra: $(basename "$e")"
done

if [ "$NO_UPLOAD" -eq 1 ]; then
  step "done (--no-upload)"
  echo "$OUT: $(find "$OUT" -type f | wc -l) files, $(du -sh "$OUT" | cut -f1)"
  exit 0
fi

# ---------------------------------------------------------------- 4. upload
step "4/4 upload $VERSION to $REPO"
[ -n "${HF_TOKEN:-}" ] || die "HF_TOKEN is not set"
command -v hf >/dev/null || die "the hf CLI is not installed"
nfiles=$(find "$OUT" -type f | wc -l)
echo "uploading $nfiles files"
ok=0
for attempt in 1 2 3 4 5 6; do
  echo "[upload] $(date -Is) attempt $attempt"
  # upload_folder skips files whose hash already matches, so a retry resumes
  if hf upload "$REPO" "$OUT" "$VERSION" --repo-type dataset --token "$HF_TOKEN" \
       --commit-message "$VERSION: binary rewards, per-pair aggregates" \
       > /tmp/upload-$VERSION.log 2>&1; then
    ok=1; echo "[upload] $(date -Is) OK"; break
  fi
  echo "[upload] $(date -Is) failed, backing off $((attempt * 60))s"
  tail -5 /tmp/upload-$VERSION.log
  sleep $((attempt * 60))
done
[ "$ok" -eq 1 ] || die "upload failed after 6 attempts; see /tmp/upload-$VERSION.log"

step "verify the uploaded tree against the Hub"
REPO="$REPO" VERSION="$VERSION" EXPECT="$nfiles" python3 - <<'PY' || die "uploaded tree does not match local"
import json, os, re, sys, urllib.request
repo, ver, expect = os.environ['REPO'], os.environ['VERSION'], int(os.environ['EXPECT'])
NEXT = re.compile(r'<([^>]+)>;\s*rel="next"')
url = (f"https://huggingface.co/api/datasets/{repo}/tree/main/{ver}"
       f"?recursive=true&limit=1000")
seen = pages = 0
while url:
    pages += 1
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {os.environ['HF_TOKEN']}"})
    with urllib.request.urlopen(req, timeout=300) as r:
        body, link = r.read(), r.headers.get('link', '')
    seen += sum(1 for e in json.loads(body) if e['type'] == 'file')
    m = NEXT.search(link or '')
    url = m.group(1) if m else None
    if pages > 500:
        sys.exit('runaway pagination')
print(f"hub {ver} files={seen} local={expect} pages={pages}")
sys.exit(0 if seen == expect else 1)
PY

step "done"
echo "$VERSION published: $nfiles files"
