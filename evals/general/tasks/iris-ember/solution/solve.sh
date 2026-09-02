#!/bin/bash
# Oracle for tasks/iris-ember (executes-deliverable).
#
# Authors /app/schedule.py (the deliverable program), makes it executable, then
# RUNS it against the fixture availability so every real result artifact at
# /app (earliest_slot.ics, personals/*.txt, summary.txt) is produced by
# executing the deliverable — never copied from the reference suite. The per-
# person snapshots are produced by schedule.py discovering and driving the
# provided person_producer.py tool. None of the tests are consulted here.
set -eu

# Write the deliverable program into /app (this is the real work being done).
cp /solution/schedule.py /app/schedule.py
chmod +x /app/schedule.py

# Run the deliverable: parse availability, compute the earliest buffer-aware
# slot, emit the conformant ICS, drive the per-person producer, write summary.
python3 /app/schedule.py

# Deliverables that running the deliverable must create under /app:
#   /app/earliest_slot.ics          the standards-conformant iCalendar event
#   /app/personals/*.txt            one per-person snapshot per attendee
#   /app/summary.txt                the short textual report
# Fail loudly if any of them is missing after the run.
for f in /app/earliest_slot.ics /app/summary.txt /app/personals/*.txt; do
    if [ ! -e "$f" ]; then
        echo "oracle: missing deliverable $f" >&2
        exit 1
    fi
done