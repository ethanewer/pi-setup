#!/bin/bash
# Oracle solution for item-038-hard: implements the deterministic fairness-first
# batch scheduler per the prose rules and writes schedule.json + audit.json.
set -uo pipefail

cat > /app/scheduler.py <<'PY'
import json, math

def load(path="/app/workload.json"):
    return json.load(open(path))

def main():
    w = load()
    capacity = w["capacity"]
    rate = w["rate"]
    shapes = w["shapes"]
    reqs = w["requests"]

    # ---- static graph inference: undirected compatibility ----
    adj = {s["id"]: {s["id"]} for s in shapes}
    for s in shapes:
        for o in s.get("compatible", []):
            adj[s["id"]].add(o)
            adj[o].add(s["id"])
    def compatible(a, b):
        return b in adj[a]

    R = sorted(reqs, key=lambda r: (r["arrival"], r["id"]))
    by = {r["id"]: r for r in R}
    info = {r["id"]: {"served": 0, "start": 0, "finish": 0} for r in R}
    batches = []
    queue = []
    t = 0
    remaining = len(R)
    while remaining > 0:
        for r in R:
            if r["arrival"] <= t and not info[r["id"]]["served"] and r["id"] not in queue:
                queue.append(r["id"])
        if not queue:
            t = min(r["arrival"] for r in R if not info[r["id"]]["served"])
            continue
        oldest = min(queue, key=lambda i: (by[i]["arrival"], by[i]["id"]))
        L = by[oldest]
        cand = [i for i in queue if compatible(L["shape"], by[i]["shape"])]
        cand.sort(key=lambda i: (by[i]["arrival"], by[i]["id"]))
        batch = []
        batch_shapes = set()
        tot = 0
        for i in cand:
            r = by[i]
            if all(compatible(r["shape"], sh) for sh in batch_shapes) and tot + r["tokens"] <= capacity:
                batch.append(i)
                batch_shapes.add(r["shape"])
                tot += r["tokens"]
        if not batch:
            batch = [oldest]
            tot = by[oldest]["tokens"]
        dur = max(1, math.ceil(tot / rate))
        st = t
        fn = t + dur
        batches.append({"start": st, "finish": fn, "duration": dur, "requests": list(batch)})
        for i in batch:
            info[i].update(served=1, start=st, finish=fn)
            queue.remove(i)
            remaining -= 1
        t = fn

    makespan = max(info[i]["finish"] for i in info)
    reqout = []
    total_tokens = 0
    for r in sorted(reqs, key=lambda r: r["id"]):
        inf = info[r["id"]]
        wait = inf["finish"] - r["arrival"]
        total_tokens += r["tokens"]
        reqout.append({
            "id": r["id"], "shape": r["shape"], "arrival": r["arrival"],
            "tokens": r["tokens"], "deadline": r["deadline"],
            "start": inf["start"], "finish": inf["finish"], "wait": wait,
            "late": inf["finish"] > r["deadline"],
        })

    metrics = {
        "makespan": makespan,
        "mean_wait": round(sum(x["wait"] for x in reqout) / len(reqout), 6),
        "max_wait": max(x["wait"] for x in reqout),
        "deadline_misses": sum(1 for x in reqout if x["late"]),
        "throughput_tokens_per_time": round(total_tokens / makespan, 6),
        "total_requests": len(reqout),
        "total_tokens": total_tokens,
    }
    schedule = {"batches": batches, "requests": reqout, "metrics": metrics}
    json.dump(schedule, open("/app/schedule.json", "w"), indent=1)

    # ---- audit: re-scan our own schedule ----
    ids = {r["id"] for r in reqs}
    served_ids = set()
    serv_only_once = True
    for r in schedule["requests"]:
        if r["id"] in served_ids:
            serv_only_once = False
        served_ids.add(r["id"])
    allonce = (served_ids == ids) and serv_only_once and len(served_ids) == len(reqs)

    start_ge = all(r["start"] >= r["arrival"] for r in schedule["requests"])
    last_finish = None
    contiguous = True
    for b in schedule["batches"]:
        if last_finish is not None and b["start"] != last_finish:
            contiguous = False
        if b["finish"] < b["start"]:
            contiguous = False
        last_finish = b["finish"]
    cap_ok = all(
        sum(by[i]["tokens"] for i in b["requests"]) <= capacity
        for b in schedule["batches"]
    )
    checks = {
        "start_not_before_arrival": start_ge and allonce,
        "single_server_contiguous": contiguous,
        "all_served_exactly_once": allonce,
        "capacity_respected": cap_ok,
    }
    audit = {"checks": checks, "passes": all(checks.values())}
    json.dump(audit, open("/app/audit.json", "w"), indent=1)

if __name__ == "__main__":
    main()
PY

python3 /app/scheduler.py