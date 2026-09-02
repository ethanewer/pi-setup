#!/bin/bash
# Verifier for item-015-main: checks the invited slot in invite.ics and decision.json.
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json, re

reward = 0.0
d = {}
try:
    d = json.load(open('/app/decision.json'))
except Exception:
    pass

EXP_START = '2024-11-18T16:00:00Z'
EXP_END   = '2024-11-18T17:00:00Z'
EXP_ROOM  = 'Meeting Room A'

ics_start = ics_end = ics_room = None
try:
    ics = open('/app/invite.ics').read()
    m = re.search(r'DTSTART:(\d{8}T\d{6}Z)', ics)
    n = re.search(r'DTEND:(\d{8}T\d{6}Z)', ics)
    l = re.search(r'LOCATION:([^\r\n]+)', ics)
    ics_start = m.group(1) if m else None
    ics_end   = n.group(1) if n else None
    ics_room  = (l.group(1).strip() if l else None)
except Exception:
    pass

def to_iso(tok):
    if not tok or len(tok) < 15:
        return None
    return f"{tok[0:4]}-{tok[4:6]}-{tok[6:8]}T{tok[9:11]}:{tok[11:13]}:00Z"

dec_start = d.get('start_utc'); dec_end = d.get('end_utc'); dec_room = d.get('room')
ok_start = (dec_start == EXP_START) and (to_iso(ics_start) == EXP_START)
ok_end   = (dec_end == EXP_END)    and (to_iso(ics_end)   == EXP_END)
ok_room  = (dec_room == EXP_ROOM)  and (ics_room == EXP_ROOM)

if ok_start and ok_end and ok_room:
    reward = 1.0
elif ok_room and (ok_start or ok_end):
    reward = 0.5
elif ok_room or ok_start:
    reward = 0.25
print(f"{reward:.2f}")
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt