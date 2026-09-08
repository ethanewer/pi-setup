#!/usr/bin/env bash
# Build the v3.9 overlay: eleven never-measured trials replaced by re-runs.
#
#   pi/deepseek          5 trials, all from general-pi-dsk        -> all 5 pass
#   claude-code/glm      6 trials, all from general-claude-glm    -> 5 pass, 1 keeps its 0
#
# The one that keeps its zero is aurora-reef: it timed out again, but after 8 real
# model turns and 3 tool calls, so that is a legitimate timeout and a real result.
# Every other trial here had produced no assistant turn at all in the original run
# and was therefore not a measurement.
#
# The claude-code six needed two attempts. The first re-run omitted
# ANTHROPIC_BASE_URL and ANTHROPIC_API_KEY and never reached OpenRouter; it is
# quarantined as v39-cc-glm-stalls-INVALID-noenv. The second produced four valid
# trials plus hinge-lathe (AgentSetupTimeoutError, zero-byte log) and sable-quill
# (ApiConnectionClosedError after one synthetic turn), which the third job retried.
#
# check_agent_actually_ran.py gates the overlay. It is run over every trial being
# published and the build stops if any of them failed to reach the model, because a
# no-op run is indistinguishable from a bad model run in the reward files alone.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
STAGE=/tmp/v39-stage
OUT=/tmp/v39-overlay
PUB=/tmp/hf-upload/v3.8
rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE" "$OUT"

collect () { # jobname harness model_plain model_meta
  python3 "$EVAL/tools/collect_task_records.py" --jobs "$JOBS" --out "$STAGE/$1" \
    --allow-missing --job "$1:$2:$3:$4" > "$STAGE/$1.log" 2>&1
  echo "[v39]   $1 -> $(find "$STAGE/$1" -name trajectory.json 2>/dev/null | wc -l) records"
}
echo "[v39] $(date -Is) collecting the re-runs"
collect v39-pi-dsk-stalls  pi          'deepseek/deepseek-v4-flash-0731' 'openrouter/deepseek/deepseek-v4-flash-0731'
collect v39-cc-glm-fixed   claude-code 'z-ai/glm-5.3-flash'             'z-ai/glm-5.3-flash'
collect v39-cc-glm-retry   claude-code 'z-ai/glm-5.3-flash'             'z-ai/glm-5.3-flash'

echo "[v39] $(date -Is) selecting the authoritative trial per task"
python3 - <<'PY'
import json, shutil, sys
from pathlib import Path
STAGE=Path('/tmp/v39-stage'); OUT=Path('/tmp/v39-overlay'); PUB=Path('/tmp/hf-upload/v3.8')
JOBS=Path('/home/ee/general-eval-runs/jobs')
# Later jobs supersede earlier ones for the same (harness, model, task): the retry
# job exists precisely because two trials in v39-cc-glm-fixed were invalid.
ORDER=['v39-pi-dsk-stalls','v39-cc-glm-fixed','v39-cc-glm-retry']
chosen={}
for job in ORDER:
    for tj in (STAGE/job).rglob('trajectory.json'):
        rel=tj.parent.relative_to(STAGE/job)   # harness/provider/model/task
        if len(rel.parts)!=4: continue
        rt=tj.parent/'verifier/reward.txt'
        if not rt.is_file():
            print('  skip %s: collector refused it (no reward.txt)' % '/'.join(rel.parts))
            continue
        st=json.loads((tj.parent/'metadata.json').read_text()).get('source_trial')
        chosen[(rel.parts[0],'/'.join(rel.parts[1:3]),rel.parts[3])]=(job,tj.parent,st)
print('  authoritative trials: %d' % len(chosen))
byjob={}
for k,(job,src,st) in chosen.items(): byjob.setdefault(job,[]).append(k)
for j in ORDER: print('     %-22s %d' % (j, len(byjob.get(j,[]))))
trial_dirs=[]
for (h,model,task),(job,src,st) in sorted(chosen.items()):
    dest=OUT/h/model/task
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists(): shutil.rmtree(dest)
    shutil.copytree(src,dest)
    if st: trial_dirs.append(str(JOBS/job/st))
# binarize under the documented contract: new = 1 exactly where old >= 1.0
n=0
for rt in OUT.rglob('verifier/reward.txt'):
    raw=rt.read_text().strip()
    try: v=float(raw)
    except ValueError: continue
    norm='1' if v>=1.0 else '0'
    if norm!=raw: rt.write_text(norm+'\n'); n+=1
print('  binarized reward files: %d' % n)
json.dump({'%s|%s|%s'%k: v[0] for k,v in chosen.items()}, open('/tmp/v39_chosen.json','w'), indent=1)
Path('/tmp/v39_trial_dirs.txt').write_text('\n'.join(trial_dirs)+'\n')
PY
sel=$?
[ $sel -eq 0 ] || { echo "[v39] selection failed"; exit 1; }

echo "[v39] $(date -Is) gating exactly the trials being published"
GATE=(); while read -r t; do [ -n "$t" ] && GATE+=(--trial "$t"); done < /tmp/v39_trial_dirs.txt
python3 "$EVAL/tools/check_agent_actually_ran.py" "${GATE[@]}" || {
  echo "[v39] FATAL: a trial being published never reached the model. Not building v3.9."; exit 1; }

echo "[v39] $(date -Is) verifying the overlay against v3.8"
python3 - <<'PY'
import json, sys, collections
from pathlib import Path
OUT=Path('/tmp/v39-overlay'); PUB=Path('/tmp/hf-upload/v3.8')
recs=sorted(d for d in OUT.rglob('metadata.json'))
bad=[]; nonbinary=[]; moved=[]
for md in recs:
    d=md.parent; rel=d.relative_to(OUT)
    for f in ('trajectory.json','metadata.json','verifier/reward.txt'):
        if not (d/f).is_file(): bad.append((str(rel),f))
    v=(d/'verifier/reward.txt').read_text().strip()
    if v not in ('0','1'): nonbinary.append((str(rel),v))
    old=PUB/rel/'verifier/reward.txt'
    if old.is_file() and old.read_text().strip()!=v:
        moved.append((str(rel), old.read_text().strip(), v))
    # every overlay record must replace an existing published record
    if not (PUB/rel).is_dir(): bad.append((str(rel),'not in v3.8'))
print('  overlay records            : %d' % len(recs))
print('  missing files / unknown    : %d %s' % (len(bad), bad[:3]))
print('  non-binary rewards         : %d %s' % (len(nonbinary), nonbinary[:3]))
print('  reward changes vs v3.8     : %d' % len(moved))
for m in sorted(moved): print('       %-56s %s -> %s' % m)
per=collections.Counter()
for m in moved: per['/'.join(m[0].split('/')[:2])]+=1
print('  by pair: %s' % dict(per))
ok = not bad and not nonbinary and len(recs)==11
print('OVERLAY_OK' if ok else 'OVERLAY_BAD')
json.dump({'moved':moved,'per_pair':dict(per)}, open('/tmp/v39_overlay_stats.json','w'), indent=1)
sys.exit(0 if ok else 1)
PY
rc=$?
echo "[v39] $(date -Is) verify rc=$rc"
exit $rc
