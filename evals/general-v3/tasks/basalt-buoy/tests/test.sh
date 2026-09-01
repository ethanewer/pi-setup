#!/bin/bash
# Verifier for basalt-buoy: checks the visible deliverables, ENFORCES the
# no-modify rule on /app/input/requests.json, and EXECUTES /app/relay.py on the
# visible snapshot and on every hidden snapshot in /tests/hidden, validating
# the emitted plan against all seven drain constraints. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_SNAPSHOT_SHA="263fec19c8d84e8e9a057c6fc5e1fb231a6f6c5ccbf46ac1df51c2126e481ead"

no_modify_broken=0
if [ ! -f /app/input/requests.json ]; then
    echo "no-modify: /app/input/requests.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/input/requests.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SNAPSHOT_SHA" ]; then
        echo "no-modify: /app/input/requests.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, re, subprocess, sys

PLANNER = "/app/relay.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible snapshot modified or missing (no-modify rule)")


def validate(inp_path, plan_path):
    """Return None if the plan satisfies every constraint, else a reason."""
    try:
        with open(inp_path) as f:
            inp = json.load(f)
        with open(plan_path) as f:
            plan = json.load(f)
    except Exception as e:
        return "unreadable: %s" % e
    try:
        budget = inp["budget"]
        reqs = inp["requests"]
        G = budget["granule"]; B = budget["batch_cap"]; F = budget["fanout"]
        C = budget["cycle_cap"]; M = budget["cycle_max"]
        if set(plan.keys()) != {"budget", "cycles"}:
            return "plan keys must be exactly budget+cycles"
        if plan["budget"] != budget:
            return "budget not echoed unchanged"
        idx = {r["id"]: k for k, r in enumerate(reqs)}
        if len(idx) != len(reqs):
            return "duplicate ids in input stream"
        seen = set()
        pos = 0
        cycle_ids, batch_ids = set(), set()
        for k, cyc in enumerate(plan["cycles"]):
            if not isinstance(cyc, dict) or set(cyc.keys()) != {"cycle_id", "units", "batches"}:
                return "cycle %d: bad shape" % k
            cid = cyc["cycle_id"]
            if not isinstance(cid, str) or cid != "c%d" % k:
                return "cycle %d: cycle_id must be 'c%d' in order" % (k, k)
            batches = cyc["batches"]
            if not isinstance(batches, list) or not batches:
                return "cycle %d: must hold >=1 batch" % k
            cu = 0
            for m, b in enumerate(batches):
                if not isinstance(b, dict) or set(b.keys()) != {"batch_id", "requests", "units"}:
                    return "cycle %d batch %d: bad shape" % (k, m)
                bid = b["batch_id"]
                if not isinstance(bid, str) or bid != "c%d-b%d" % (k, m):
                    return "cycle %d batch %d: batch_id must be 'c%d-b%d'" % (k, m, k, m)
                if bid in batch_ids:
                    return "duplicate batch_id %s" % bid
                batch_ids.add(bid)
                rids = b["requests"]
                if not isinstance(rids, list) or not rids:
                    return "batch %s: empty" % bid
                if len(rids) > F:
                    return "batch %s: fanout exceeded (%d > %d)" % (bid, len(rids), F)
                for rid in rids:
                    if rid not in idx:
                        return "unknown id %s" % rid
                    if rid in seen:
                        return "duplicated id %s" % rid
                    seen.add(rid)
                runs = [idx[r] for r in rids]
                if runs != list(range(runs[0], runs[0] + len(runs))):
                    return "batch %s: not a consecutive run of the stream" % bid
                if runs[0] != pos:
                    return "batch %s: out of arrival order" % bid
                pos = runs[-1] + 1
                units = sum(reqs[t]["units"] for t in runs)
                if b["units"] != units:
                    return "batch %s: units %s != sum of member units %s" % (bid, b["units"], units)
                if units <= 0 or units % G != 0:
                    return "batch %s: units %d not a positive multiple of granule %d" % (bid, units, G)
                if units > B:
                    return "batch %s: units %d > batch_cap %d" % (bid, units, B)
                cu += units
            if cyc["units"] != cu:
                return "cycle %s: units %s != sum of batches %s" % (cid, cyc["units"], cu)
            if cu > C:
                return "cycle %s: units %d > cycle_cap %d" % (cid, cu, C)
        if pos != len(reqs):
            return "missing ids: only %d of %d requests shipped" % (pos, len(reqs))
        if len(plan["cycles"]) > M:
            return "cycle count %d > cycle_max %d" % (len(plan["cycles"]), M)
    except Exception as e:
        return "validation error: %s" % e
    return None


def run_case(inp, out):
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, PLANNER, inp, out],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        return "planner failed to run: %s" % e
    if r.returncode != 0:
        return "planner exited %d: %s" % (r.returncode, r.stderr[-200:])
    if not os.path.isfile(out):
        return "planner wrote no output"
    return None


if not os.path.isfile(PLANNER):
    failures.append("missing /app/relay.py")
else:
    # --- visible case: re-run the planner, then validate the shipped plan ---
    if os.path.isfile("/app/input/requests.json"):
        err = run_case("/app/input/requests.json", "/tmp/bb_verify_plan.json")
        if err:
            failures.append("visible re-run: %s" % err)
        else:
            err = validate("/app/input/requests.json", "/tmp/bb_verify_plan.json")
            if err:
                failures.append("visible re-run plan invalid: %s" % err)
    else:
        failures.append("visible snapshot missing")

    # --- visible deliverable: /app/plan.json must exist and be valid ---
    if not os.path.isfile("/app/plan.json"):
        failures.append("missing /app/plan.json")
    elif os.path.isfile("/app/input/requests.json"):
        err = validate("/app/input/requests.json", "/app/plan.json")
        if err:
            failures.append("shipped /app/plan.json invalid: %s" % err)

    # --- hidden snapshots: run the planner and validate each plan ---
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(os.listdir(hidden))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            inp = os.path.join(hidden, c, "requests.json")
            if not os.path.isfile(inp):
                failures.append("hidden '%s' malformed" % c)
                continue
            out = "/tmp/bb_hidden_plan.json"
            err = run_case(inp, out)
            if err:
                failures.append("hidden '%s': %s" % (c, err))
                continue
            err = validate(inp, out)
            if err:
                failures.append("hidden '%s' plan invalid: %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
