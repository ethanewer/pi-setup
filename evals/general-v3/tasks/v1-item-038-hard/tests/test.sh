#!/bin/bash
# Verifier for item-038-hard. Compares the agent's schedule.json to a precomputed
# reference and audits structural invariants. Writes 0..1 to reward.txt unconditionally.
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json, sys

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None

sched = load("/app/schedule.json")
audit = load("/app/audit.json")
ref = load("/tests/reference/reference.json")

if sched is None or ref is None:
    print("0.00"); sys.exit(0)

points = 0

reqs = sched.get("requests", [])
batches = sched.get("batches", [])
by = {x["id"]: x for x in reqs}
ref_ids = {r["id"] for r in ref["requests"]}

# ---------- structural: start >= arrival, contiguous single server, ids match ----------
structural = True
for r in reqs:
    if r["start"] < r["arrival"] or r["finish"] < r["start"]:
        structural = False
for i in ref_ids:
    if i not in by or by[i]["finish"] is None:
        structural = False
if len(by) != len(ref_ids):
    structural = False
last = -1
for b in batches:
    if last != -1 and b["start"] != last:
        structural = False
    last = b["finish"]

# ---------- capacity respected (recompute from input workload) ----------
cap_ok = False
try:
    wrk = json.load(open("/app/workload.json"))
    cap = wrk["capacity"]
    cap_ok = all(
        sum(next((x["tokens"] for x in reqs if x["id"] == i), 0) for i in b.get("requests", []))
        <= cap for b in batches
    )
except Exception:
    cap_ok = False

# ---------- match reference schedule (per request start/finish) ----------
sched_match = all(
    by.get(r["id"]) is not None
    and by[r["id"]]["start"] == r["start"]
    and by[r["id"]]["finish"] == r["finish"]
    for r in ref["requests"]
)

# ---------- metrics match (with tolerance) ----------
m = sched.get("metrics", {})
rm = ref["metrics"]
def close(a, b, tol=1e-5):
    return abs(a - b) <= tol

metrics_match = (
    m.get("makespan") == rm["makespan"]
    and close(m.get("mean_wait", 0.0), rm["mean_wait"])
    and m.get("max_wait") == rm["max_wait"]
    and m.get("deadline_misses") == rm["deadline_misses"]
    and close(m.get("throughput_tokens_per_time", 0.0), rm["throughput_tokens_per_time"])
)

# ---------- audit: all booleans true, passes true ----------
audit_ok = False
if isinstance(audit, dict):
    checks = audit.get("checks")
    if isinstance(checks, dict) and checks:
        audit_ok = all(isinstance(v, bool) and v for v in checks.values()) and audit.get("passes") is True

if structural:
    points += 40
if cap_ok:
    points += 10
if sched_match:
    points += 35
if metrics_match:
    points += 10
if audit_ok:
    points += 5

print(f"{points/100.0:.2f}")
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt