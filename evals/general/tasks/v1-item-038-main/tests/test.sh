#!/bin/bash
# Verifier for item-038-main. Recomputes the deterministic FIFO schedule from
# /app/workload.json and compares the agent's /app/schedule.json against it.
mkdir -p /logs/verifier

reward=0
if python3 - <<'PY'
import json, math, sys

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None

work = load("/app/workload.json")
sched = load("/app/schedule.json")
if work is None or sched is None:
    sys.exit(1)

rate = work["rate"]
jobs = sorted(work["jobs"], key=lambda j: (j["arrival"], j["id"]))
scheduled = {j["id"]: False for j in jobs}
by = {j["id"]: j for j in jobs}
exp = []
t = 0
remaining = len(jobs)
while remaining > 0:
    queue = [j["id"] for j in jobs if j["arrival"] <= t and not scheduled[j["id"]]]
    if not queue:
        t = min(j["arrival"] for j in jobs if not scheduled[j["id"]])
        continue
    front = queue[0]
    j = by[front]
    dur = max(1, math.ceil(j["tokens"] / rate))
    exp.append({"id": j["id"], "start": t, "finish": t + dur, "wait": t + dur - j["arrival"]})
    scheduled[j["id"]] = True
    remaining -= 1
    t += dur

exp_by = {e["id"]: e for e in exp}
got_by = {s["id"]: s for s in sched.get("jobs", [])}

def close(a, b):
    return isinstance(a, (int, float)) and isinstance(b, (int, float)) and abs(a - b) < 1e-9

match = (len(got_by) == len(exp_by)
         and all(k in got_by and close(got_by[k]["start"], e["start"])
                 and close(got_by[k]["finish"], e["finish"])
                 and close(got_by[k]["wait"], e["wait"]) for k, e in exp_by.items()))

m = sched.get("metrics", {})
metrics_ok = (m.get("makespan") == max(e["finish"] for e in exp)
              and m.get("total_tokens") == sum(j["tokens"] for j in jobs)
              and m.get("total_jobs") == len(jobs))

if match and metrics_ok:
    print("PASS")
    sys.exit(0)
else:
    print("FAIL")
    sys.exit(1)
PY
then
    reward=1
fi
echo "$reward" > /logs/verifier/reward.txt