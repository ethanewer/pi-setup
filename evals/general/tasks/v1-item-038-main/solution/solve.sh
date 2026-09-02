#!/bin/bash
set -euo pipefail

cat > /app/simulate.py <<'PY'
import json, math

def load():
    with open("/app/workload.json") as f:
        return json.load(f)

def main():
    w = load()
    rate = w["rate"]
    jobs = sorted(w["jobs"], key=lambda j: (j["arrival"], j["id"]))
    remaining = len(jobs)
    scheduled = {j["id"]: False for j in jobs}
    by = {j["id"]: j for j in jobs}
    schedule = []
    t = 0
    while remaining > 0:
        queue = []
        for j in jobs:
            if j["arrival"] <= t and not scheduled[j["id"]]:
                queue.append(j["id"])
        if not queue:
            t = min(j["arrival"] for j in jobs if not scheduled[j["id"]])
            continue
        front = queue[0]
        j = by[front]
        dur = max(1, math.ceil(j["tokens"] / rate))
        start = t
        finish = t + dur
        schedule.append({"id": j["id"], "arrival": j["arrival"], "tokens": j["tokens"],
                         "start": start, "finish": finish, "wait": finish - j["arrival"]})
        scheduled[j["id"]] = True
        remaining -= 1
        t = finish

    schedule.sort(key=lambda s: s["id"])
    out = {
        "jobs": schedule,
        "metrics": {
            "makespan": max(s["finish"] for s in schedule),
            "total_tokens": sum(s["tokens"] for s in schedule),
            "total_jobs": len(schedule),
        },
    }
    with open("/app/schedule.json", "w") as f:
        json.dump(out, f)

if __name__ == "__main__":
    main()
PY

python3 /app/simulate.py
echo "wrote /app/schedule.json"