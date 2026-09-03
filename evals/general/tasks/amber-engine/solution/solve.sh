#!/bin/bash
#
# amber-engine oracle. Does the real work: brings up the offsite stack,
# obtains the planning phrase from the coordinator desk as planner PLN-47,
# holds phrase-authenticated conversations with Mara, Jonas and Priya through
# the interactive dialers, parses their availability/ranks/constraints,
# applies the documented decision rule, writes /app/offsite_plan.json and
# books it. Never reads /tests.
set -euo pipefail

cd /opt/offsite

# ---- 1. Bring the four microservices up.
bash up.sh

# ---- 2. Get the phrase + budget from the coordinator desk.
printf 'PLN-47\n' | bash dial/dial_coordinator.sh > /tmp/cs_coord.out
PHRASE=$(sed -n 's/^PHRASE=//p' /tmp/cs_coord.out)
BUDGET=$(sed -n 's/^BUDGET=//p' /tmp/cs_coord.out)
[ -n "$PHRASE" ] || { echo "oracle: no phrase from coordinator desk" >&2; exit 1; }

# ---- 3. Authenticated conversation with each colleague (phrase -> all three
#         questions -> BYE), transcripts kept for aggregation.
for person in mara jonas priya; do
  printf '%s\nAVAILABILITY\nPREFERENCES\nCONSTRAINTS\nBYE\n' "$PHRASE" \
    | bash "dial/dial_${person}.sh" > "/tmp/cs_${person}.out"
  grep -q 'AVAILABILITY=' "/tmp/cs_${person}.out" \
    || { echo "oracle: ${person} shared no data" >&2; exit 1; }
done

# ---- 4. Aggregate: apply the documented decision rule to the collected
#         availability, ranks and constraints.
BUDGET="$BUDGET" python3 - <<'PY'
import json
import os
import re

BUDGET = int(os.environ["BUDGET"])

# The company offsite catalog (as published in the task instructions).
catalog = {
    "escape-room":     {"venue": "cipher-hall",            "cost": 25,
                        "slots": ["10:00", "14:00"], "step_free": True,
                        "outdoor": False},
    "cooking-class":   {"venue": "salt-and-ember-kitchen", "cost": 55,
                        "slots": ["09:30", "13:00"], "step_free": False,
                        "outdoor": False},
    "trail-hike":      {"venue": "kestrel-ridge-loop",     "cost": 10,
                        "slots": ["08:30"],          "step_free": False,
                        "outdoor": True},
    "board-game-cafe": {"venue": "meeple-and-mug",         "cost": 15,
                        "slots": ["11:00", "15:00"], "step_free": True,
                        "outdoor": False},
}

people = {}
for name in ("mara", "jonas", "priya"):
    text = open("/tmp/cs_%s.out" % name).read()
    avail = re.search(r"AVAILABILITY=(\S+)", text).group(1).split(",")
    ranks = {a: int(r) for a, r in
             re.findall(r"([a-z-]+):(\d+)",
                        re.search(r"RANKS=(\S+)", text).group(1))}
    cons = re.search(r"CONSTRAINTS=(.+)", text).group(1).strip()
    people[name] = {"avail": set(avail), "ranks": ranks, "cons": cons}

# 1. date: in the availability of all three colleagues.
dates = people["mara"]["avail"] & people["jonas"]["avail"] & people["priya"]["avail"]
assert len(dates) == 1, "expected exactly one common date, got %s" % dates
date = sorted(dates)[0]

# 2. activity: budget-feasible and satisfying every hard constraint,
#    minimizing the sum of ranks.
kills = set()
for p in people.values():
    cons = p["cons"]
    for m in re.finditer(r"\bno ([a-z-]+)\b", cons):
        if m.group(1) in catalog:
            kills.add(m.group(1))
    if re.search(r"outdoor", cons):
        kills |= {a for a, i in catalog.items() if i["outdoor"]}
    if re.search(r"step-free|wheelchair", cons):
        kills |= {a for a, i in catalog.items() if not i["step_free"]}

candidates = [a for a, i in catalog.items()
              if a not in kills and i["cost"] <= BUDGET]
assert candidates, "no activity survives budget + constraints"
activity = min(candidates,
               key=lambda a: sum(p["ranks"][a] for p in people.values()))
venue = catalog[activity]["venue"]

# 3. start_time: earliest slot conflicting with no one's time block.
blocks = {}  # date -> "blocked until" time per person
for p in people.values():
    for d, t in zip(re.findall(r"\d{4}-\d{2}-\d{2}", p["cons"]),
                    re.findall(r"until (\d{2}:\d{2})", p["cons"])):
        blocks.setdefault(d, []).append(t)
slots = [s for s in catalog[activity]["slots"]
         if all(s >= t for t in blocks.get(date, []))]
assert slots, "no slot of %s is free on %s" % (activity, date)
start_time = slots[0]

plan = {"date": date, "activity": activity, "venue": venue,
        "start_time": start_time}
with open("/app/offsite_plan.json", "w") as fh:
    json.dump(plan, fh)
    fh.write("\n")
print("oracle: plan =", json.dumps(plan))
PY

# ---- 5. Book it: the desk must accept the plan.
bash book.sh /app/offsite_plan.json > /tmp/cs_book.out
grep -q '"booked"' /tmp/cs_book.out \
  || { echo "oracle: booking desk rejected the plan" >&2; cat /tmp/cs_book.out >&2; exit 1; }

echo "amber-engine oracle complete -> /app/offsite_plan.json (booked)"
