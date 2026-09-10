# dutywheel

Small, dependency-free Python package that assigns on-call duty cycles to a
crew of engineers.  No third-party runtime dependencies.

## What it does

A crew roster is a JSON document (see `samples/engineering.json`):

```json
{
  "team": "engineering",
  "members": [
    {"id": "ada-lovelace", "name": "Ada Lovelace",
     "role": "primary",
     "windows": [{"start": "2026-05-18T05:00:00Z", "end": "2026-05-18T12:00:00Z"}]}
  ]
}
```

- `dutywheel.crew.load_roster(path)` — load and validate a roster.
- `dutywheel.rotation.pick(team, previous=None, now=None)` — choose the
  member who carries the next duty cycle.  Members with an overlapping
  maintenance window at `now` are deprioritised; among equally available
  members the choice is intended to be fully reproducible: the same roster
  snapshot must always produce the same assignment, in every process and on
  every retry.
- `dutywheel.schedule.build_weeks(roster, start_date, weeks=4)` — build a
  weekly on-call table.
- `dutywheel.schedule.render_table(schedule)` — render it as text.

## CLI

```console
$ python3 -m dutywheel schedule samples/engineering.json --start 2026-11-02 --weeks 4
$ python3 -m dutywheel next samples/engineering.json
```

## Tests

```console
$ python3 -m pytest -q tests/
```