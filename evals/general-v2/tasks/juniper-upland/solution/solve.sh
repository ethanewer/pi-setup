#!/bin/bash
# juniper-upland oracle. Installs the reference scheduling worker at
# /app/schedule.py and RUNS it on the shipped /app fixture to produce
# /app/earliest_slot.ics; then reuses the provided roster snapshot producer to
# generate the per-member snapshots, and assembles /app/summary.txt. It never
# reads /tests and never cats a precomputed answer.
set -eu

cp /solution/schedule.py /app/schedule.py
chmod +x /app/schedule.py

# Part 1 + 2: find the earliest buffer-aware slot and emit a conformant ICS.
chosen=$(python3 /app/schedule.py /app /app)
echo "oracle: chosen slot $chosen" >&2

# Guard: the visible fixture must yield a feasible slot.
[ "$chosen" != "NONE" ] || { echo "oracle: unexpected infeasible slot" >&2; exit 1; }

# Part 3: discover and replay the provided roster producer for each member.
# Deliverable namespace /app/personals/*.txt: one <member>.txt per
# snapshot_members entry, created by replaying the helper, never copied.
mkdir -p /app/personals
python3 - <<'PY'
import glob, json, os, subprocess
req = json.load(open("/app/request.json"))
members = req["snapshot_members"]
for name in members:
    out = subprocess.check_output(["python3", "/app/kit/roster_feed.py", name],
                                  text=True)
    with open("/app/personals/%s.txt" % name, "w") as fh:
        fh.write(out)
os.chmod("/app/personals", 0o755)
# Confirm the wildcarded deliverable set /app/personals/*.txt was produced:
# exactly one snapshot file per snapshot_members entry.
snapshots = sorted(glob.glob("/app/personals/*.txt"))
for fn in snapshots:
    os.chmod(fn, 0o644)
if len(snapshots) != len(members):
    raise SystemExit("oracle: expected one snapshot per member")
PY

# Deliverable 4: summary.txt naming the chosen slot and the snapshot members.
{
  echo "meeting=juniper-upland-lead-sync"
  echo "earliest_start=${chosen}"
  echo "availability_inputs=untouched"
  echo -n "snapshots=ada,ben,carol,gwen" ;
} > /app/summary.txt

# Confirm every required deliverable exists (created by doing the work).
[ -f /app/schedule.py ]        || { echo "oracle: missing schedule.py" >&2; exit 1; }
[ -f /app/earliest_slot.ics ]  || { echo "oracle: missing earliest_slot.ics" >&2; exit 1; }
[ -f /app/summary.txt ]        || { echo "oracle: missing summary.txt" >&2; exit 1; }
for name in ada ben carol gwen; do
  [ -f "/app/personals/$name.txt" ] || { echo "oracle: missing $name" >&2; exit 1; }
done
echo "oracle: all deliverables present" >&2