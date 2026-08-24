#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/minutes.txt ]; then
  if python3 - <<'PYEOF'
from icalendar import Calendar
cal = Calendar.from_ical(open('/app/events.ics', 'rb').read())
total = 0
for comp in cal.walk('VEVENT'):
    if str(comp.get('SUMMARY')).strip() == 'work':
        s = comp.decoded('DTSTART')
        e = comp.decoded('DTEND')
        total += int((e - s).total_seconds() / 60)
expected = str(total)
got = open('/app/minutes.txt').read().strip()
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt