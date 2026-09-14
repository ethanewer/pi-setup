#!/usr/bin/env bash
# Acceptance census for the v4.3c wave.
#
# Re-runs the both-direction gate over every landed task, sharded, and records
# the OBSERVED rewards parsed out of each task's raw harbor reward.txt rather
# than the gate's own PASS/FAIL line. A summary line is what a verifier writes
# about itself; the reward file is what it actually returned.
#
# This exists because the suite's own history keeps finding tasks that passed
# their author and their independent reviewer and still failed a census. Three
# earlier waves each caught at least one.
#
# Safe to run while the authoring wave is still reviewing, as long as the tasks
# under review are excluded: verify_new_task.sh uses a PID-suffixed gate cache
# and a per-task job directory, so concurrent invocations do not collide.
#
#   SHARDS=3 EXCLUDE=a,b,c bash runs/census-v43c.sh
set -uo pipefail
cd /home/ee/pi-setup/evals/general || exit 2

OUT=${OUT:-/tmp/v43c-census}
SHARDS=${SHARDS:-3}
# Tasks whose reviewer is still running would be censused mid-edit, and
# futtock-careen was never authored. Both are excluded by default.
EXCLUDE=${EXCLUDE:-companion-berm,companion-flint,crance-bell,crojack-wheel,futtock-careen}

rm -rf "$OUT"; mkdir -p "$OUT"
echo "$EXCLUDE" | tr ',' '\n' | sed '/^$/d' | sort -u > "$OUT/exclude.txt"

python3 - "$OUT" <<'PY' > "$OUT/tasks.txt"
import json, os, sys
out = sys.argv[1]
excl = set(open(f'{out}/exclude.txt').read().split())
slots = [x['name'] for x in json.load(open('specs/v43c_slots.json'))]
for n in slots:
    if n in excl:
        continue
    if os.path.exists(f'tasks/{n}/task.toml'):
        print(n)
PY

n=$(wc -l < "$OUT/tasks.txt")
echo "=== [$(date -Is)] census over $n of 107 slots, $SHARDS shards ==="
echo "    excluded: $(tr '\n' ' ' < "$OUT/exclude.txt")"
echo "    disk before: $(df -h / | awk 'NR==2{print $3" used, "$4" free"}')"
[ "$n" -gt 0 ] || { echo "nothing to do"; exit 0; }

: > "$OUT/rc.txt"
split -n r/$SHARDS -d "$OUT/tasks.txt" "$OUT/shard"
for s in "$OUT"/shard*; do
  ( while read -r t; do
      [ -n "$t" ] || continue
      bash tools/verify_new_task.sh "$t" >"$OUT/$t.log" 2>&1
      r=$?
      # Capture rc once. Reading $? a second time would report the status of the
      # echo that wrote rc.txt, which is always 0 and would hide every failure.
      echo "$t rc=$r" >> "$OUT/rc.txt"
      echo "=== [$(date -Is)] done $t rc=$r ($(wc -l < "$OUT/rc.txt")/$n)"
    done < "$s" ) &
done
wait

echo
echo "=== [$(date -Is)] census complete ==="
echo "    disk after: $(df -h / | awk 'NR==2{print $3" used, "$4" free"}')"

# Tally from the raw reward values the gate recorded, not from its rc.
python3 - "$OUT" <<'PY'
import re, sys, pathlib
out = pathlib.Path(sys.argv[1])
rc = {}
for line in (out / 'rc.txt').read_text().splitlines():
    parts = line.rsplit(' rc=', 1)
    if len(parts) == 2:
        rc[parts[0]] = parts[1]

ok, bad, nolog = [], [], []
for t in sorted(rc):
    log = out / f'{t}.log'
    if not log.exists():
        nolog.append(t); continue
    txt = log.read_text(errors='replace')
    # Parse the reward the gate read out of harbor's verifier/reward.txt. Taking
    # the gate's own PASS line instead would be trusting a summary about itself.
    pat = re.compile(r"^\s+(oracle|nop): harbor_rc=(-?\d+) reward='([^']*)'", re.M)
    got = {m.group(1): (m.group(2), m.group(3)) for m in pat.finditer(txt)}
    o, nn = got.get('oracle'), got.get('nop')
    problems = []
    if o is None: problems.append('no oracle reward line')
    elif o[1] != '1.0': problems.append(f'oracle reward={o[1]!r} (want 1.0)')
    if nn is None: problems.append('no nop reward line')
    elif nn[1] != '0.0': problems.append(f'nop reward={nn[1]!r} (want 0.0)')
    if rc.get(t) != '0': problems.append(f'gate rc={rc.get(t)}')
    (bad.append((t, problems)) if problems else ok.append(t))

print(f'censused {len(rc)} tasks: PASS {len(ok)}  FAIL {len(bad)}  no-log {len(nolog)}')
for t, p in bad:
    print(f'  FAIL {t}: ' + '; '.join(p))
for t in nolog:
    print(f'  NO LOG {t}')
if not bad and not nolog:
    print('  every task earned oracle reward 1.0 and nop reward 0.0')
PY
