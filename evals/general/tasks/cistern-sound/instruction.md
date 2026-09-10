# cistern-sound: settle the settlement report

You are handed a working repository. `/app` is a git checkout of **paygate**, a
small Python package that turns a monthly merchant ledger into a settlement
report. The package ships a runnable CLI, a unit-test suite, and a written
specification at `/app/README.md`. Everything is already on disk, the git
history is present, and the test suite is green exactly as shipped. There is no
network access during this task and none will be granted.

Your job is to make the repository deliver a settlement report that its own
specification actually supports — and to put on record, in writing, what you
decided and why. Read the specification and the shipped fixtures (the ledger,
the tests, the git history) carefully before changing anything. The interesting
property of this task is not a crash or a syntax error; it is a property of
what the specification asks for, and the shipped code currently satisfies only
part of it.

## Environment

- Python 3.12. `pytest` is installed. Everything else you need is the standard
  library; do not add third-party packages to the repository.
- `/app` is a git repository with history — `git log` is available and is worth
  reading.
- `/app/ledger.json` is the shipped (visible) ledger. Treat it as input data:
  **do not modify it**.
- No network. Do not push, clone, or reach out anywhere.

## Repository layout (for orientation)

```
/app/
  README.md                 the specification — the contract
  CHANGELOG.md              release notes
  Makefile                  `make test`, `make report`
  ledger.json               the visible ledger fixture (read-only)
  paygate/
    __init__.py, __main__.py
    models.py               Entry / Group data models
    policy.py               group-total decision logic
    report.py               ledger loading + report assembly
    cli.py                  the report CLI (deliverable)
    tests/test_report.py    the unit-test suite (green as shipped)
```

Which of these files your work touches is your call: the CLI must keep working,
the suite must stay green, and the report must satisfy the specification. You
may change source and tests as needed — this includes changing an assertion
that pins behaviour the specification no longer supports. Do not delete tests
or disable the suite.

## Deliverables

1. `/app/paygate/cli.py` — the report CLI. After your changes it must still
   satisfy the CLI contract below.
2. `/app/decisions.md` — your written decision record (required, see below).

## CLI contract (unchanged by your work)

From `/app`:

```
python3 -m paygate LEDGER.json OUT.json
```

- Reads `LEDGER.json` (schema described in the README) and writes `OUT.json`.
- Exit code 0 on a well-formed ledger. On a malformed ledger it exits non-zero
  without writing `OUT.json`.
- `OUT.json` is a JSON object with exactly these keys:

```json
{
  "period": "2026-02",
  "grand_total_cents": 749027,
  "groups": {
    "GG01": { "name": "Payroll", "count": 3, "total_cents": 456227 }
  }
}
```

  - `groups` maps every group `id` present in the ledger — and only those — to
    an object with exactly `name`, `count`, `total_cents`.
  - `name` is copied from the ledger; `count` is the number of entries in the
    group; `total_cents` is that group's single total; `grand_total_cents` is
    the sum of the displayed group totals (never a separately computed figure).
  - All amounts are integer cents end to end. No floats, no rounding.

## The specification

`/app/README.md` is the contract and every requirement in it applies. Apply
**one consistent rule to every group**: the report must not special-case a
subset of groups, and the numbers it shows must be exactly the numbers the
specification provides for.

The repository's own suite must be green when you finish:

```
cd /app && python3 -m pytest paygate/tests -q
```

The verifier runs this suite and fails the task if it does not pass.

## /app/decisions.md

Write a concise decision record (a few paragraphs; no filler). It must contain:

1. the **two specification requirements that cannot both be satisfied**,
   quoted **verbatim** from `/app/README.md`;
2. which resolution you implemented, and why you chose it over the
   alternative;
3. which shipped tests (if any) you had to change, and how.

A reader who has not seen the repository must be able to follow exactly which
requirements conflicted, why, and what you did about it.

## Quality bar

The verifier executes the CLI on the shipped ledger and on hidden ledgers and
checks the produced reports against the specification; it checks the decision
record against the README; and it re-runs the repository's test suite. Code
without a decision record, a decision record without a conforming
implementation, or a report that only satisfies part of the specification are
all failing runs.