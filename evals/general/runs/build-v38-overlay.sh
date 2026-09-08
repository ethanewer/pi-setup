#!/usr/bin/env bash
# Build the v3.8 terminus-2 overlay and check it before anything is published.
#
# Two independent things go in here:
#
#   1. All 1,570 terminus-2 records re-collected from their published source
#      trial. The previously published corpus carried 21,040 tool messages of
#      which 17,021 -- 81% -- had empty content: the older collection path emitted
#      one tool message per tool_call and left the content blank when no
#      observation matched it. Re-collected, the same trials yield 12,803 tool
#      messages, none empty, holding 27.5 MB of terminal output against 10.1 MB.
#
#   2. Six of the eight API-stall trials replaced by re-runs. Those eight timed
#      out inside _query_llm having issued no command at all, so their reward of 0
#      charged a provider outage to the model. Two of them -- ashen-lattice and
#      vine-terrace -- timed out again after 18 and 74 steps of real work, so
#      those zeros are legitimate and are kept as re-collected, not re-run.
#      harbor-gasket's first re-run died on the known tmux flake and needed a
#      second.
set -uo pipefail
FULL=/tmp/t2-full/terminus-2
STALLS=/tmp/t2-stalls/terminus-2
GASKET=/tmp/t2-gasket/terminus-2
OUT=/tmp/t2-v38/terminus-2
PUB=/tmp/hf-upload/v3.7/terminus-2
rm -rf /tmp/t2-v38; mkdir -p "$OUT"

echo "[v38] $(date -Is) base: all re-collected terminus-2 records"
cp -a "$FULL"/. "$OUT"/
echo "[v38]   $(find "$OUT" -name trajectory.json | wc -l) records"

echo "[v38] overlaying the stall re-runs"
n=0
for src in "$STALLS" "$GASKET"; do
  [ -d "$src" ] || { echo "[v38]   SKIP $src (absent)"; continue; }
  for rt in "$src"/*/*/*/verifier/reward.txt; do
    [ -f "$rt" ] || continue
    d=$(dirname "$(dirname "$rt")"); rel=${d#"$src"/}
    # never overlay a trial the collector refused: no reward.txt means the
    # outcome is undetermined and the published record must stand
    rm -rf "$OUT/$rel"; cp -a "$d" "$OUT/$rel"; n=$((n+1))
    echo "[v38]   <- $rel reward=$(cat "$rt")"
  done
done
echo "[v38]   overlaid $n re-run records"

echo "[v38] $(date -Is) verifying the overlay"
python3 - <<'PY'
import json, sys
from pathlib import Path
OUT=Path('/tmp/t2-v38/terminus-2'); PUB=Path('/tmp/hf-upload/v3.7/terminus-2')
recs=sorted(d for d in OUT.rglob('metadata.json'))
bad=[]; moved=[]; nonbinary=[]; empty_tool=0; tool_bytes=0; tool_n=0
pub_tool_bytes=pub_tool_n=pub_empty=0
for md in recs:
    d=md.parent; rel=d.relative_to(OUT)
    for f in ('trajectory.json','metadata.json','verifier/reward.txt'):
        if not (d/f).is_file(): bad.append((str(rel),f))
    rt=d/'verifier/reward.txt'
    if rt.is_file():
        v=rt.read_text().strip()
        if v not in ('0','1'): nonbinary.append((str(rel),v))
        old=PUB/rel/'verifier/reward.txt'
        if old.is_file() and old.read_text().strip()!=v:
            moved.append((str(rel), old.read_text().strip(), v))
    tj=d/'trajectory.json'
    if tj.is_file():
        for m in json.loads(tj.read_text()).get('messages',[]):
            if m.get('role')=='tool':
                c=m.get('content') or ''
                tool_n+=1; tool_bytes+=len(c)
                if not c.strip(): empty_tool+=1
for md in PUB.rglob('metadata.json'):
    d=md.parent; tj=d/'trajectory.json'
    if not tj.is_file(): continue
    for m in json.loads(tj.read_text()).get('messages',[]):
        if m.get('role')=='tool':
            c=m.get('content') or ''
            pub_tool_n+=1; pub_tool_bytes+=len(c)
            if not c.strip(): pub_empty+=1
print('  records                       : %d (expected 1570)' % len(recs))
print('  missing files                 : %d %s' % (len(bad), bad[:3]))
print('  non-binary rewards            : %d %s' % (len(nonbinary), nonbinary[:3]))
print('  reward changes vs v3.7        : %d' % len(moved))
for m in moved: print('       %-58s %s -> %s' % m)
print()
print('  tool messages   published %6d -> overlay %6d' % (pub_tool_n, tool_n))
print('  empty tool msgs published %6d -> overlay %6d' % (pub_empty, empty_tool))
print('  tool content    published %6.1f MB -> overlay %6.1f MB (%.2fx)'
      % (pub_tool_bytes/1e6, tool_bytes/1e6, tool_bytes/max(pub_tool_bytes,1)))
ok = not bad and not nonbinary and len(recs)==1570 and empty_tool==0
print()
print('OVERLAY_OK' if ok else 'OVERLAY_BAD')
json.dump({'moved':moved,'tool_messages':[pub_tool_n,tool_n],
           'empty_tool':[pub_empty,empty_tool],
           'tool_bytes':[pub_tool_bytes,tool_bytes]},
          open('/tmp/v38_overlay_stats.json','w'), indent=1)
sys.exit(0 if ok else 1)
PY
rc=$?
echo "[v38] $(date -Is) verify rc=$rc"
exit $rc
