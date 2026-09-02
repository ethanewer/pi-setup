#!/usr/bin/env python3
"""cedar-summit hidden probe: the call journal must prove the authenticated
conversations actually happened.

Requires, in /var/log/offsite/calls.jsonl:
  - the coordinator desk issued the phrase to the registered planner;
  - for each colleague: at least one phrase-authenticated session in which
    AVAILABILITY, PREFERENCES and CONSTRAINTS were all asked, and the call
    was completed (BYE after authentication).
"""
import json
import re
import sys

LOG_PATH = "/var/log/offsite/calls.jsonl"
PEOPLE = ("mara", "jonas", "priya")
QUERIES = {"AVAILABILITY", "PREFERENCES", "CONSTRAINTS"}
SESSION_RE = re.compile(r"^[0-9a-f]{6}-[0-9a-f]{10}$")


def main() -> int:
    try:
        events = [json.loads(line) for line in open(LOG_PATH)
                  if line.strip()]
    except OSError as exc:
        print("no call journal at %s: %s" % (LOG_PATH, exc))
        return 1
    except ValueError as exc:
        print("call journal is not valid JSONL: %s" % exc)
        return 1

    if not events:
        print("call journal is empty: no conversations were held")
        return 1

    issued = [e for e in events
              if e.get("service") == "coordinator"
              and e.get("event") == "phrase_issued"]
    if not issued:
        print("the coordinator desk never issued the phrase to the planner")
        return 1

    for person in PEOPLE:
        evs = [e for e in events if e.get("service") == person]
        authed = {e.get("session") for e in evs
                  if e.get("event") == "auth_ok"
                  and SESSION_RE.match(str(e.get("session", "")))}
        if not authed:
            print("%s: no phrase-authenticated session in the journal"
                  % person)
            return 1
        asked = set()
        for e in evs:
            if e.get("session") in authed:
                ev = str(e.get("event", ""))
                if ev.startswith("query:"):
                    asked.add(ev.split(":", 1)[1])
        missing = QUERIES - asked
        if missing:
            print("%s: authenticated session(s) never asked %s"
                  % (person, sorted(missing)))
            return 1
        completed = any(e.get("session") in authed
                        and e.get("event") == "completed" for e in evs)
        if not completed:
            print("%s: no authenticated call was completed with BYE" % person)
            return 1

    print("session probe passed: coordinator phrase + all three "
          "authenticated conversations logged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
