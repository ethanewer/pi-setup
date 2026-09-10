#!/usr/bin/env python3
"""Grader-side contract probe for gantry-ember.

Runs against the agent's delivered tree (/app/dutywheel) and checks the two
clauses of the rotation contract that the shipped nondeterminism violates,
without depending on any pinned PYTHONHASHSEED list:

  A. cross-process reproducibility: two fresh interpreters with DIFFERENT
     hash seeds must pick the same member for the same roster snapshot
     (the shipped wheel breaks this: its tie-break uses the interpreter's
     per-process random hash(), so winners differ across processes);
  B. previous-member exclusion: the wheel must never hand the next cycle to
     the member who carried the previous one while any other member is
     available (the shipped wheel silently ignores ``previous``).

The probe builds its own roster and exercises the wheel only through its
public API.  It exits 0 only if every check passes.
"""
import os
import subprocess
import sys
from datetime import datetime, timezone

REPO = os.environ.get("GANTRY_PROBE_REPO", "/app/dutywheel")
NOW = datetime(2026, 11, 2, 12, 0, 0, tzinfo=timezone.utc)

TEAM = [
    {"id": "milo",  "name": "Milo",  "role": "primary",   "windows": []},
    {"id": "vera",  "name": "Vera",  "role": "primary",   "windows": []},
    {"id": "noah",  "name": "Noah",  "role": "secondary", "windows": []},
    {"id": "ivy",   "name": "Ivy",   "role": "secondary", "windows": []},
    {"id": "simon", "name": "Simon", "role": "fallback",  "windows": []},
]

CHILD = (
    "import sys\n"
    "sys.path.insert(0, %r)\n"
    "from datetime import datetime, timezone\n"
    "from dutywheel.rotation import pick\n"
    "team = %r\n"
    "print(pick(team, previous=None, now=datetime(2026, 11, 2, 12, 0, 0,"
    " tzinfo=timezone.utc))['id'])\n"
) % (REPO, TEAM)


def main() -> int:
    sys.path.insert(0, REPO)
    problems = []

    # ---- A. same snapshot, different processes, different hash seeds -----
    winners = set()
    for seed in (11, 222, 33333, 4444444, 987654321):
        env = dict(os.environ)
        env["PYTHONHASHSEED"] = str(seed)
        proc = subprocess.run(
            [sys.executable, "-c", CHILD],
            capture_output=True, text=True, timeout=60, env=env)
        if proc.returncode != 0:
            problems.append(
                "reproducibility child probe crashed under seed %s: %s"
                % (seed, (proc.stderr or proc.stdout)[-300:]))
            continue
        winners.add(proc.stdout.strip())
    if len(winners) != 1:
        problems.append(
            "selection is not reproducible across processes: different "
            "hash seeds produced winners %r" % sorted(winners))

    # ---- B. the previous on-call member is never re-selected ------------
    from dutywheel.rotation import pick
    for member in TEAM:
        picked = pick(TEAM, previous=member, now=NOW)
        if picked["id"] == member["id"]:
            problems.append(
                "wheel re-selected the previous on-call member (%s) while "
                "other members were available" % member["id"])

    if problems:
        print("PROBE FAILURES:")
        for p in problems:
            print("  - " + p)
        return 1
    print("contract probe OK: selection reproducible across processes; "
          "previous member excluded")
    return 0


if __name__ == "__main__":
    sys.exit(main())