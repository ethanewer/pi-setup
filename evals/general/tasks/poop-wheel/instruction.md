# Secrets findings block CI for every validation state

## Situation

`/app/src` is a shallow, pinned clone of the semgrep repository
(`https://github.com/semgrep/semgrep`) at upstream commit
`ae531156ca6f2f692827696723e35b786fb7fa92`, checked out in detached HEAD.
Its `semgrep_interfaces` submodule is checked out, the Python package is
installed editable from the tree, and `pytest`, `pytest-mock` and
`pytest-snapshot` are installed. Everything works fully offline:
there is **no network** at trial time, so `git fetch`, `pip install`,
`curl` and any other network use will fail.

## The bug

Semgrep secrets rules can be paired with a validator. When a validator runs,
each resulting finding carries a *validation state* — `valid`, `invalid`,
`error`, or "no validator ran". Rules control CI blocking through two
metadata knobs:

- a general rule action, `dev.semgrep.actions` (e.g. `["monitor"]` or `["block"]`), and
- per-state actions, `dev.semgrep.validation_state.actions`, a map like
  `{"valid": "comment", "invalid": "monitor", "error": "block"}`.

The intended semantics: a finding that **has** a validation state should be
blocked or not **exclusively** by the per-state action for the state that
actually matched — the general action is irrelevant for such findings. A
finding with **no** validation state (no validator ran) should use the
general rule action. A finding blocks CI only when the consulted action is
exactly `"block"`.

In this checkout that is not what happens. The general rule action leaks
into the decision for every validated finding: with a rule whose general
action is `"block"`, an **invalid** finding whose per-state `invalid` action
is `"monitor"` still blocks CI, and a **valid** finding whose per-state
`valid` action is `"comment"` still blocks CI. A validator rule configured
to block only one state therefore blocks everything.

The project's own unit tests already contain the regression cases for this
behaviour. The two test files that matter are
`cli/tests/default/unit/test_rule_match.py` (rule/finding matching) and
`cli/tests/default/unit/test_rule.py` (rule parsing). Run them now:

```
cd /app/src
python3 -m pytest cli/tests/default/unit/test_rule_match.py cli/tests/default/unit/test_rule.py -q
```

Today `test_rule_match.py` reports **3 failing cases** out of its 16 — those
three failing regression cases are exactly this bug. `test_rule.py` passes.
After a correct fix, the two files together report `19 passed`.

## Deliverables

### 1. `/app/reproduce.py` — your own reproduction of the bug

Write a self-contained reproduction script that demonstrates the bug with
the project's own Python API, and keep it as a deliverable. Contract:

- It must construct real `semgrep.rule_match.RuleMatch` findings in code
  (import the installed package, build the findings, call
  `finding.is_blocking`). Do not hardcode the outcome.
- It must cover at least these scenarios (each: a finding with the given
  metadata/validation state, and the blocking decision the **correct**
  behaviour requires). All use a per-state map and a general action as
  described above unless stated:
  - `invalid` validation state, per-state `invalid` = `"monitor"`,
    general action `["block"]` → must **not** block;
  - `valid` validation state, per-state `valid` = `"comment"`,
    general action `["block"]` → must **not** block;
  - `error` validation state, per-state `error` = `"monitor"`,
    general action `["block"]` → must **not** block;
  - no validation state (no validator), general action `["block"]` → **must** block;
  - no validation state, per-state map all `"block"`, general action
    `["monitor"]` → must **not** block.
- Output contract: print one line per scenario, either `ok ` or `BUG `
  followed by a short scenario name and the observed and expected values;
  then print a final summary line exactly `REPRO: N failing` where N is the
  number of scenarios whose actual decision disagreed with the required one;
  exit with code 0 if N == 0, and non-zero otherwise.

Run it against the tree **before** you change anything:

```
cd /app/src && python3 /app/reproduce.py
```

It must exit non-zero with `REPRO:` reporting at least one failing scenario
(the bug). That failing reproduction is what you verify the fix against.

### 2. A repaired `/app/src` tree

Fix the bug in the checked-out tree so that:

- the three failing regression cases above pass, and
  `pytest cli/tests/default/unit/test_rule_match.py cli/tests/default/unit/test_rule.py -q`
  reports `19 passed`;
- `/app/reproduce.py` reports `REPRO: 0 failing` and exits 0 when run
  against the repaired tree, while the same script still reports failing
  scenarios when run against an untouched tree (the bug genuinely detected);
- the semantics at the top are honoured for any combination of general
  action, per-state map and validation state, as the regression tests
  demand (for instance: a per-state `"block"` for the state that matched
  must still block even if the general action is `"monitor"`, and a finding
  with no validation state must still block when the general action is
  `"block"` no matter what the per-state map says).

The tests in the tree are the spec: take them as authoritative.

## Constraints

- Network is unavailable; everything needed is installed.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: keep HEAD at the pinned commit, do not fetch, commit,
  rewrite history, add remotes, or change the `semgrep_interfaces`
  submodule, and do not add, delete or rename files inside the repository.
  The verifier checks that the tree differs from the pinned commit only in
  the minimal source change that fixes the bug plus the regression-test
  file the image already carries.
- The unit-test file `cli/tests/default/unit/test_rule_match.py` in the tree
  is byte-identical to the upstream regression test the image ships; the
  verifier requires it to stay that way. Do not edit it, skip its cases or
  delete it — pass them.
- `/app/reproduce.py` must not modify anything under `/app/src` or any
  other path outside `/app` when it runs.
- `/opt/golden`, `/opt/pristine`, `/tests` and `/solution` are
  harness-owned; do not read or modify them.
- `pytest` needs `-p no:cacheprovider` only if you want a perfectly clean
  tree; it is not required for correctness.

## What the verifier checks

1. Tree provenance: `/app/src` is still at the pinned commit, the upstream
   fix commit is not reachable from the clone, the regression-test file is
   byte-identical to the upstream regression test, and the only changes to
   the tree are the source fix plus that overlaid test file.
2. Your reproduction: run against a pristine (untouched) copy of the tree
   it must exit non-zero with at least one failing scenario; run against
   the repaired tree it must exit 0 with `REPRO: 0 failing`.
3. The project's own tests: the two files above report `19 passed`, and the
   7 parametrized validator-blocking regression cases all pass.
4. Hidden cases: additional combinations of validation states, action maps
   and general actions that the upstream regression cases do not use, all
   checked against the correct semantics.

Deliverables: the repaired `/app/src` tree and `/app/reproduce.py`.