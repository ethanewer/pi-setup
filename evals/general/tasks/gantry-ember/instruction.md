# gantry-ember — make the on-call rotation suite green, every time

The image ships a small, self-contained Python project, **`/app/dutywheel`**:
an on-call rotation tool for a crew of engineers, with a real test suite
(16 tests across three modules, runnable with `python3 -m pytest -q tests/`
from the project root). It has no third-party runtime dependencies.

The suite has a problem: **it fails intermittently**. Most full runs pass,
but occasionally one test goes red for no apparent reason, and nobody can
reproduce it on demand. Run the suite repeatedly and it will show up —
often within a dozen runs, sometimes not for longer.

Your job: make the full suite pass **reliably** — the exact protocol the
grader runs is below — without deleting, skipping, weakening, or editing any
test, and without weakening what the suite verifies.

## Environment

| Path | What it is |
|---|---|
| `/app/dutywheel` | the project to fix (package under `dutywheel/`, samples under `samples/`) |
| `/app/dutywheel/tests/` | the test suite (frozen — see constraints) |
| `/app/dutywheel/.git` | repository history; `git log`/`git blame` are fair game |
| `/app/dutywheel/samples/engineering.json` | the sample crew roster the tests load |

Python 3.12 and `pytest` are installed; there is no network at trial time.

## The project contract

`dutywheel` assigns each on-call duty cycle to one member of a crew. The
rotation contract the suite enforces:

- every cycle is carried by a member of the crew;
- the member who carried the previous cycle is not handed the next one
  while any other member is available;
- the selection is reproducible: the same roster snapshot picks the same
  member in every process and on every retry.

## How the grader measures "reliable"

It runs the full suite **20 consecutive times**, requiring all tests to pass
with none skipped or failed, then **20 more times** with
`PYTHONHASHSEED` set to a different value for each run, again requiring a
clean pass every time. (This is the standard way CI systems reproduce
intermittent hash-seed-dependent failures — you can use the same lever while
debugging; the shipped tests never read it themselves.) It then applies two
**hidden source mutations** and requires the suite to **fail** under each,
proving the tests still detect real regressions. Finally it byte-hashes
every shipped test file and rejects any modification to them, and it probes
the rotation contract directly — same snapshot picks the same member in
every process, previous on-call member never re-selected while anyone else
is available — by exercising the wheel itself.

## Constraints

- **Do not modify, delete, skip, or disable any test** — the shipped test
  files are byte-checked by the grader. Fix the behavior, not the test.
- You may change any other file under `/app/dutywheel` (except the samples
  must keep the roster valid for the suite).
- Keep all 16 tests running and passing; none may be skipped, xfailed, or
  deselected.
- The fix must be deterministic: the suite must stay green across the 40
  runs described above, and regressions must still be caught.

## Deliverable

`/app/dutywheel` — the fixed project, in place. When you are done, 40
consecutive full-suite runs (20 as-is and 20 under different
`PYTHONHASHSEED` values) must all be green, with every test still running
and no test edited.