#!/bin/bash
set -euo pipefail
cat > /app/parse.py <<'PYEOF'
from icalendar import Calendar
cal = Calendar.from_ical(open('/app/events.ics', 'rb').read())
total = 0
for comp in cal.walk('VEVENT'):
    if str(comp.get('SUMMARY')).strip() == 'work':
        start = comp.decoded('DTSTART')
        end = comp.decoded('DTEND')
        total += int((end - start).total_seconds() / 60)
open('/app/minutes.txt', 'w').write(str(total))
PYEOF
python3 /app/parse.py