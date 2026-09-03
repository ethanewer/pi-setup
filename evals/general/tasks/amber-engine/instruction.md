# Amber Engine: negotiate the Tern Systems team offsite over the phone

Tern Systems is planning a one-day team offsite for four people: you (the
designated planner) and three colleagues — **Mara**, **Jonas** and **Priya**.
Each colleague runs a small "phone" microservice on this machine, and the
**coordinator desk** microservice issues the planning phrase and runs the
booking desk. Your job is to bring the stack up, call each colleague through
the provided interactive dialer scripts, gather their availability,
preferences and constraints, and work out the one plan the group would
choose.

Nothing is running when you start. The stack lives under `/opt/offsite`:

| Piece | What it is |
|---|---|
| `/opt/offsite/up.sh` | starts all four microservices (idempotent) |
| `/opt/offsite/down.sh` / `status.sh` | stop / health snapshot |
| `/opt/offsite/dial/dial_coordinator.sh` | interactive coordinator-desk dialer |
| `/opt/offsite/dial/dial_mara.sh` | interactive phone dialer — Mara, port 8702 |
| `/opt/offsite/dial/dial_jonas.sh` | interactive phone dialer — Jonas, port 8703 |
| `/opt/offsite/dial/dial_priya.sh` | interactive phone dialer — Priya, port 8704 |
| `/opt/offsite/book.sh [plan.json]` | submits a plan JSON to the booking desk |

The dialer scripts are interactive: they read each line you type, POST it to
the corresponding microservice, and print the answer. You are expected to use
them (or reproduce their HTTP protocol exactly).

## The phone protocol

- The coordinator desk (`dial_coordinator.sh`) asks for your **planner id**.
  You are registered as planner **`PLN-47`**. If the id checks out, the desk
  hands you the **offsite phrase** and the **per-person budget**.
- Each colleague's phone only talks planning after you give them the exact
  offsite phrase. A wrong or stale phrase ends the call immediately and they
  share nothing.
- Once the phrase is accepted, you may ask (in any order, uppercase):
  `AVAILABILITY`, `PREFERENCES`, `CONSTRAINTS`. End the call with `BYE`.
  Data lines come back as `KEY=value` payload lines.
- Colleagues are busy people: a call that goes nowhere gets hung up on.

## The offsite catalog (company-negotiated rates)

| activity | venue | cost/person | duration | start slots | venue step-free |
|---|---|---|---|---|---|
| `escape-room` | `cipher-hall` | €25 | 2 h | 10:00, 14:00 | yes |
| `cooking-class` | `salt-and-ember-kitchen` | €55 | 3 h | 09:30, 13:00 | no (three floors, no elevator) |
| `trail-hike` | `kestrel-ridge-loop` | €10 | 4 h | 08:30 | n/a (mountain trail) |
| `board-game-cafe` | `meeple-and-mug` | €15 | 3 h | 11:00, 15:00 | yes |

The offsite must happen on one weekday of the week **2026-03-09 …
2026-03-13** (Mon–Fri).

## The decision rule (this is what you are graded on)

1. **date** — must lie in the availability of *all three* colleagues (the
   collected availabilities admit exactly one such date).
2. **activity** — among catalog activities that (a) fit the coordinator's
   per-person budget and (b) violate none of the colleagues' hard
   constraints, pick the one minimizing the **sum of the colleagues' ranks**
   (each colleague ranks 1 = favourite).
3. **venue** — fixed by the chosen activity per the catalog.
4. **start_time** — the earliest slot of the chosen activity that conflicts
   with no colleague's time block on the chosen date.

The booking desk only confirms that a submitted plan is *feasible* — it does
not tell you whether it is the one the group would choose, and it closes
after six submissions. Work the decision out from what the colleagues tell
you.

## Deliverable

`/app/offsite_plan.json` — a JSON object with **exactly** these string keys:

```json
{"date": "YYYY-MM-DD", "activity": "<catalog id>", "venue": "<venue id>", "start_time": "HH:MM"}
```

## Constraints

- Bring the stack up with `/opt/offsite/up.sh`; it must be serving at the end
  of your session.
- Do not modify anything under `/opt/offsite` — dial with the scripts or raw
  HTTP, but leave the services as they are.
- All communication is loopback-only; no external network is available.

## Hidden-test behavior you should know about

The grader brings the stack up (idempotently), checks your plan file, and
re-validates it against the group's hidden state. It also reads the services'
call journal: each colleague must show a completed, phrase-authenticated
conversation in which availability, preferences **and** constraints were all
asked, and the coordinator desk must show that the phrase was legitimately
issued to the registered planner. Finally, it confirms the phones still hang
up on a wrong phrase — so do not weaken the auth to make your life easier.
