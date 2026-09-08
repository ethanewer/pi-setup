#!/usr/bin/env bash
# Re-collect every terminus-2 record from its published source trial.
#
# v3.7 restored 80 records, found by flagging any published terminus-2 transcript
# with no tool message, no tool call and no reasoning at all. That heuristic was
# too narrow. 1,787 of the 12,803 raw observation steps carry no synthesized
# tool_calls, and records that happened to keep some reasoning were therefore not
# flagged -- 114 records still publish fewer tool messages than their raw trial
# holds observations, 426 observation steps missing in total. ashen-vane
# published 13 messages with 0 tool results against a raw trial with 13 steps,
# 12 of them carrying observations.
#
# The committed collector is already correct: it emits a tool message for every
# observation result, ungated by tool_calls. These records were simply never
# re-collected with it. So rather than guess a detector a second time, collect all
# of them and let the raw trials be the authority.
#
# Selection is driven by each record's published source_trial, not by a scan, so
# the output cannot silently substitute a different attempt at the same task.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
PUB=/tmp/hf-upload/v3.7
STAGE=/tmp/t2-jobs
OUT=/tmp/t2-full
rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE" "$OUT"

# Enumerate the jobs from the trials themselves rather than from a hand-written
# list. The first attempt covered six job names and missed 146 published records,
# because the v3.3/v3.4/v3.5 repair runs put their terminus-2 trials in their own
# job directories. config.json names the agent and the model, so read that.
JOBLIST=/tmp/t2_jobs.json
python3 - > "$JOBLIST" <<'PY'
import json
from pathlib import Path
JOBS=Path('/home/ee/general-eval-runs/jobs')
rows=[]
for j in sorted(JOBS.iterdir()):
    if not j.is_dir(): continue
    ts=sorted(j.glob('*__*/'))
    if not ts: continue
    cfg=ts[0]/'config.json'
    if not cfg.is_file(): continue
    try: c=json.loads(cfg.read_text())
    except Exception: continue
    ag=c.get('agent')
    if not isinstance(ag,dict) or ag.get('name')!='terminus-2': continue
    mn=ag.get('model_name') or ''
    if 'glm' in mn:      model='z-ai/glm-5.3-flash'
    elif 'deepseek' in mn: model='deepseek/deepseek-v4-flash-0731'
    else: continue
    rows.append([j.name, model])
print(json.dumps(rows))
PY
echo "[t2full] $(date -Is) collecting each terminus-2 job separately ($(python3 -c "import json;print(len(json.load(open('$JOBLIST'))))" ) jobs)"
python3 -c "
import json,sys
for job,model in json.load(open('$JOBLIST')): print(job+'|'+model)" | while IFS='|' read -r job model; do
  [ -d "$JOBS/$job" ] || { echo "[t2full]   SKIP $job (absent)"; continue; }
  python3 "$EVAL/tools/collect_task_records.py" --jobs "$JOBS" --out "$STAGE/$job" \
    --allow-missing --job "$job:terminus-2:$model:openrouter/$model" \
    > "$STAGE/$job.log" 2>&1
  echo "[t2full]   $job -> $(find "$STAGE/$job" -name trajectory.json 2>/dev/null | wc -l) records"
done

echo "[t2full] $(date -Is) selecting per published source_trial"
python3 - <<'PY'
import json, shutil, sys
from pathlib import Path
PUB=Path('/tmp/hf-upload/v3.7'); STAGE=Path('/tmp/t2-jobs'); OUT=Path('/tmp/t2-full')
# index every collected record by (model, task) -> list of (job, source_trial, path)
idx={}
for tj in STAGE.rglob('trajectory.json'):
    if tj.parent==STAGE: continue
    rel=tj.relative_to(STAGE)
    parts=rel.parts                      # job / terminus-2 / provider / model / task
    if len(parts)<6 or parts[1]!='terminus-2': continue
    job=parts[0]; model='/'.join(parts[2:4]); task=parts[4]
    md=tj.parent/'metadata.json'
    st=json.loads(md.read_text()).get('source_trial') if md.is_file() else None
    idx.setdefault((model,task),[]).append((job,st,tj.parent))

# Key the index by source_trial rather than by task name. harbor truncates the
# task name in the trial directory (32 characters, and it drops a trailing
# hyphen, so v1-skill-semaphores-concurrency-limits becomes
# v1-skill-semaphores-concurrency), which makes the collected task name a lossy
# rendering of the published one. The trial id is exact and is what the published
# record already names, so match on that and let the task name come from the
# published path.
by_trial={}
for (model,task),v in idx.items():
    for job,st,src in v:
        if st: by_trial.setdefault((model,st),[]).append((job,st,src))

missing=[]; ambiguous=[]; taken=0; notfound=[]
for md in (PUB/'terminus-2').rglob('metadata.json'):
    rel=md.parent.relative_to(PUB/'terminus-2')
    if len(rel.parts)!=3: continue
    model='/'.join(rel.parts[:2]); task=rel.parts[2]
    want=json.loads(md.read_text()).get('source_trial')
    cands=by_trial.get((model,want),[])
    if not cands:
        (notfound if want else missing).append((model,task,want))
        continue
    if len({c[0] for c in cands})>1: ambiguous.append((model,task,want,[c[0] for c in cands]))
    job,_,src=cands[0]
    dest=OUT/'terminus-2'/rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists(): shutil.rmtree(dest)
    shutil.copytree(src,dest); taken+=1
print('  published terminus-2 records      : %d' % (taken+len(missing)+len(notfound)))
print('  matched to their source_trial     : %d' % taken)
print('  record names no source_trial      : %d %s' % (len(missing), missing[:3]))
print('  source_trial not among collected  : %d %s' % (len(notfound), notfound[:3]))
print('  matched more than one job         : %d %s' % (len(ambiguous), ambiguous[:3]))
json.dump({'taken':taken,'missing':missing,'notfound':notfound,'ambiguous':ambiguous},
          open('/tmp/t2_full_select.json','w'), indent=1)
if missing or notfound: sys.exit(1)
PY
rc=$?
echo "[t2full] $(date -Is) selection rc=$rc  output records=$(find "$OUT" -name trajectory.json | wc -l)"
echo "T2FULL_DONE rc=$rc"
exit $rc
