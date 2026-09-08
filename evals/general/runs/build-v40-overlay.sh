#!/usr/bin/env bash
# Build the v3.10 overlay: seven records replaced.
#
#   hollow-notch, all six pairs   the task no longer disables DNS, so four pairs
#                                 that previously could not call the API at all
#                                 can now attempt it. Four of the six pass. All
#                                 six are re-run rather than only the four that
#                                 were broken, because the task changed and
#                                 leaving terminus-2 on the old version would
#                                 compare a different task against the others.
#   rust-bazaar, claude-code/dsk  reward unchanged at 0, but the record was two
#                                 user messages and no assistant turn. Re-run it
#                                 produced 86 assistant turns, 64 tool calls and
#                                 35,323 output tokens, and still failed, so the
#                                 zero is now a measurement rather than an empty
#                                 transcript.
#
# The gate runs over exactly the trials being published and stops the build if any
# of them never reached the model.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
STAGE=/tmp/v40-stage
OUT=/tmp/v40-overlay
PUB=/tmp/hf-upload/v3.9
rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE" "$OUT"

collect () { # jobname harness model_plain model_meta
  python3 "$EVAL/tools/collect_task_records.py" --jobs "$JOBS" --out "$STAGE/$1" \
    --allow-missing --job "$1:$2:$3:$4" > "$STAGE/$1.log" 2>&1
  echo "[v40]   $1 -> $(find "$STAGE/$1" -name trajectory.json 2>/dev/null | wc -l) records"
}
echo "[v40] $(date -Is) collecting"
collect v40-hn-cc-glm        claude-code 'z-ai/glm-5.3-flash'              'z-ai/glm-5.3-flash'
collect v40-hn-cc-dsk        claude-code 'deepseek/deepseek-v4-flash-0731' 'deepseek/deepseek-v4-flash-0731'
collect v40-hn-pi-glm        pi          'z-ai/glm-5.3-flash'              'openrouter/z-ai/glm-5.3-flash'
collect v40-hn-pi-dsk        pi          'deepseek/deepseek-v4-flash-0731' 'openrouter/deepseek/deepseek-v4-flash-0731'
collect v40-hn-t2-glm        terminus-2  'z-ai/glm-5.3-flash'              'openrouter/z-ai/glm-5.3-flash'
collect v40-hn-t2-dsk        terminus-2  'deepseek/deepseek-v4-flash-0731' 'openrouter/deepseek/deepseek-v4-flash-0731'
collect v40-cc-dsk-hollowrust claude-code 'deepseek/deepseek-v4-flash-0731' 'deepseek/deepseek-v4-flash-0731'

echo "[v40] $(date -Is) selecting the authoritative trial per record"
python3 - <<'PY'
import json, shutil
from pathlib import Path
STAGE=Path('/tmp/v40-stage'); OUT=Path('/tmp/v40-overlay'); JOBS=Path('/home/ee/general-eval-runs/jobs')
# v40-cc-dsk-hollowrust holds both a hollow-notch retry that failed on a provider
# error and the good rust-bazaar record; the six v40-hn-* jobs supersede it for
# hollow-notch, so list it first.
ORDER=['v40-cc-dsk-hollowrust','v40-cc-glm-hollow',
       'v40-hn-cc-glm','v40-hn-cc-dsk','v40-hn-pi-glm','v40-hn-pi-dsk',
       'v40-hn-t2-glm','v40-hn-t2-dsk']
chosen={}
for job in ORDER:
    for tj in (STAGE/job).rglob('trajectory.json'):
        rel=tj.parent.relative_to(STAGE/job)      # harness/provider/model/task
        if len(rel.parts)!=4: continue
        if not (tj.parent/'verifier/reward.txt').is_file():
            print('  skip %s: collector refused it (no reward.txt)' % '/'.join(rel.parts))
            continue
        st=json.loads((tj.parent/'metadata.json').read_text()).get('source_trial')
        key=(rel.parts[0],'/'.join(rel.parts[1:3]),rel.parts[3])
        if job=='v40-cc-dsk-hollowrust' and rel.parts[3]=='hollow-notch':
            continue          # superseded by v40-hn-cc-dsk
        chosen[key]=(job,tj.parent,st)
byjob={}
for k,(job,src,st) in chosen.items(): byjob.setdefault(job,[]).append(k[2])
print('  authoritative trials: %d' % len(chosen))
for j in ORDER:
    if j in byjob: print('     %-24s %s' % (j, sorted(byjob[j])))
tdirs=[]
for (h,model,task),(job,src,st) in sorted(chosen.items()):
    dest=OUT/h/model/task
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists(): shutil.rmtree(dest)
    shutil.copytree(src,dest)
    if st: tdirs.append(str(JOBS/job/st))
n=0
for rt in OUT.rglob('verifier/reward.txt'):
    raw=rt.read_text().strip()
    try: v=float(raw)
    except ValueError: continue
    norm='1' if v>=1.0 else '0'
    if norm!=raw: rt.write_text(norm+'\n'); n+=1
print('  binarized reward files: %d' % n)
Path('/tmp/v40_trial_dirs.txt').write_text('\n'.join(tdirs)+'\n')
json.dump({'%s|%s|%s'%k: v[0] for k,v in chosen.items()}, open('/tmp/v40_chosen.json','w'), indent=1)
PY

echo "[v40] $(date -Is) gating exactly the trials being published"
GATE=(); while read -r t; do [ -n "$t" ] && GATE+=(--trial "$t"); done < /tmp/v40_trial_dirs.txt
python3 "$EVAL/tools/check_agent_actually_ran.py" "${GATE[@]}" || {
  echo "[v40] FATAL: a trial being published never reached the model"; exit 1; }

echo "[v40] $(date -Is) verifying the overlay against v3.9"
python3 - <<'PY'
import json, sys, collections
from pathlib import Path
OUT=Path('/tmp/v40-overlay'); PUB=Path('/tmp/hf-upload/v3.9')
recs=sorted(d for d in OUT.rglob('metadata.json'))
bad=[]; nonbinary=[]; moved=[]
for md in recs:
    d=md.parent; rel=d.relative_to(OUT)
    for f in ('trajectory.json','metadata.json','verifier/reward.txt'):
        if not (d/f).is_file(): bad.append((str(rel),f))
    v=(d/'verifier/reward.txt').read_text().strip()
    if v not in ('0','1'): nonbinary.append((str(rel),v))
    old=PUB/rel/'verifier/reward.txt'
    if not (PUB/rel).is_dir(): bad.append((str(rel),'not in v3.9'))
    elif old.read_text().strip()!=v: moved.append((str(rel), old.read_text().strip(), v))
print('  overlay records        : %d (expected 7)' % len(recs))
print('  missing files / unknown: %d %s' % (len(bad), bad[:3]))
print('  non-binary rewards     : %d %s' % (len(nonbinary), nonbinary[:3]))
print('  reward changes vs v3.9 : %d' % len(moved))
for m in sorted(moved): print('       %-58s %s -> %s' % m)
per=collections.Counter('%s/%s' % tuple(m[0].split('/')[:2]) for m in moved)
print('  by pair: %s' % dict(per))
ok = not bad and not nonbinary and len(recs)==7
print('OVERLAY_OK' if ok else 'OVERLAY_BAD')
json.dump({'moved':moved,'per_pair':dict(per)}, open('/tmp/v40_overlay_stats.json','w'), indent=1)
sys.exit(0 if ok else 1)
PY
rc=$?
echo "[v40] $(date -Is) verify rc=$rc"
exit $rc
