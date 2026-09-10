# Halyard Yard — write the alerting rules

The Halyard container-freight yard service is already installed and running
its own test suite at `/app/yard`. It has **four** sub-systems — gate
reception, stacker cranes, reefer cold storage, and rail dispatch — and each
sub-system has exactly one observable failure mode. Those failure modes are
turning into real production incidents because no one has written the alerting
rules yet. Your job is to write them.

## What you will produce

Create **one** Prometheus alerting rules file:

```
/app/alerting/alerts.yml
```

It must be a valid Prometheus rule group that realises the four Halyard
failure modes as concrete alerts.

## The environment

- Prometheus tooling is installed: `promtool` is on `PATH`
  (`promtool --version`). Networking is disabled, so everything you need is
  already on disk.
- The Halyard yard source lives at `/app/yard`. **`/app/yard/docs/runbook.md`
  is the authoritative operational document.** It defines every metric the
  service emits, every threshold, and the exact alerting contract. Implement
  what it says.
- `/app/yard/src/yard/alerting.py` pins the same operational constants in code
  (the app's pytest suite checks runbook and code agree).
- `/app/yard/monitoring/prometheus.yml` shows how the rules file is wired into
  the stack.
- A Ready-made unit-test scenario ships at
  `/app/yard/monitoring/tests/visible_scenario.yml`. It exercises the four
  alert names on their must-fire conditions. You can run
  `promtool test rules /app/yard/monitoring/tests/visible_scenario.yml` after
  writing `alerts.yml` to check your work locally.

## Output contract

`/app/alerting/alerts.yml` must satisfy all of the following:

1. It is readable by `promtool check rules /app/alerting/alerts.yml` (no
   parse or validation errors).
2. It defines **exactly four** rules with exactly these alert names, from the
   runbook's four failure modes:
   - `GateBacklogFault`
   - `StackerFaultStorm`
   - `ReeferColdChain`
   - `DispatchAgeSLA`
3. Every rule sets the label `severity: page` and inherits the identifying
   label of the series that triggers it (one of `lane`, `crane`, `unit`,
   `depot`) — no other labels.
4. Each alert **fires on its real failure condition** and **does not fire on a
   healthy-but-busy system**, exactly as the runbook specifies (which metrics,
   which thresholds, and over which sustained windows).

## How it is graded

The verifier runs two kinds of check against your `alerts.yml`:

- `promtool check rules /app/alerting/alerts.yml` — syntactic validity.
- `promtool test rules <scenario>` — unit-tests asserting **which alerts fire
  at which evaluation time** on a given input series. It runs the shipped
  visible scenario plus **four hidden scenarios** mounted at `/tests/hidden`.
  The hidden scenarios include healthy-but-busy input series that the rules
  must **not** fire on.

A rule that fires on a healthy-but-busy system (over-broad) fails the task
exactly as much as a rule that misses a real failure (under-sensitive). Both
kinds of mistake are caught by the hidden scenarios, so read the runbook
carefully and make every alert discriminate.

Your rules file must pass **all** of these scenarios before the task earns a
reward.

## Constraints

- Work only in `/app/alerting/`. Do not modify anything under `/app/yard`
  (the shipped repo and its metrics are inputs, not deliverables).
- Do not read or rely on the hidden scenarios under `/tests` — they are not
  available to you at runtime and your solution must not depend on them.
- Everything runs with a single CPU; no parallel service is required.
