#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
jobs = json.load(open('/app/fab_jobs.json'))
sched = json.load(open('/app/schedule.json'))
assert set(sched) == set(jobs)
# map machine -> list of (start, end)
machine_intervals = {}
for job_name in jobs:
    steps = jobs[job_name]
    entries = sched[job_name]
    assert len(entries) == len(steps)
    by_step = {int(e['step']): e for e in entries}
    prev_end = -1
    for i, step in enumerate(steps):
        s = int(by_step[i]['start'])
        assert s >= 0, (job_name, i, s)
        dur = int(step['duration'])
        assert s >= prev_end, (job_name, i)
        prev_end = s + dur
        mach = step['machine']
        ops = machine_intervals.setdefault(mach, [])
        for (s2, e2) in ops:
            assert s + dur <= s2 or e2 <= s, (mach, s, s+dur, s2, e2)
        ops.append((s, s + dur))
# also check an explicit answer exists
assert len(sched) >= 1
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt