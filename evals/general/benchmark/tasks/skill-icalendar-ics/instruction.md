`/app/events.ics` is an iCalendar file containing three `VEVENT`s. Use the **`icalendar`** Python library to parse it.

Write `/app/parse.py`, which:
1. reads `/app/events.ics`,
2. walks all `VEVENT` components,
3. for every event whose `SUMMARY` equals exactly `work`, adds its duration in whole minutes (`DTEND` minus `DTSTART`),
4. writes the total minutes (as an integer string) to `/app/minutes.txt`.

The file `/app/events.ics` is (all timestamps are UTC `Z`):
```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//bench//EN
BEGIN:VEVENT
SUMMARY:work
DTSTART:20240115T090000Z
DTEND:20240115T113000Z
END:VEVENT
BEGIN:VEVENT
SUMMARY:meeting
DTSTART:20240116T100000Z
DTEND:20240116T110000Z
END:VEVENT
BEGIN:VEVENT
SUMMARY:work
DTSTART:20240117T140000Z
DTEND:20240117T150000Z
END:VEVENT
END:VCALENDAR
```

The two `work` events span 09:00–11:30 (150 minutes) and 14:00–15:00 (60 minutes), so the expected total is `210`.

Run `/app/parse.py` so `/app/minutes.txt` is produced. The verifier uses the same library to recompute.