# yoke-lattice — author a CI workflow and a local runner that executes it

You are building a small, self-contained **CI pipeline runner** for a demo
repository. You write two deliverables:

1. `/app/run_pipeline.sh` — an executable **shell script** that acts as a local
   GitHub Actions runner: it parses a workflow YAML, topologically orders the
   jobs, runs each job's steps in a clean shell, honours `needs:` and `if:`,
   and writes per-job artifacts plus a machine-readable summary.
2. `/app/.github/workflows/ci.yml` — a real workflow for this repository with
   **three or more jobs** connected by a `needs:` dependency graph, using only
   the documented subset below, whose steps drive the shipped repository.

The verifier runs **your** runner against **your** workflow, and then against
three *hidden* workflow fixtures with different job graphs. So the runner must
be a general tool implementing the contract below exactly; nothing in it may
depend on this repository, its file names, or the shipped workflow's shape.

## What is already on disk

- `/app` is a small Python project ("yoke"): a lattice-grid toolkit with a
  `Makefile`, a `yoke/` package, and a `tests/` suite (green under pytest). Its
  CLI is `python -m yoke lint|build|render`. A real CI for it builds, tests and
  packages the tree.
- `python3.12`, `pytest` and PyYAML are installed. `bash` is available.
- You may create files anywhere under `/app`. Do **not** modify `/tests`.
- The verifier may execute your workflow more than once on the same `/app`; make
  the workflow's steps idempotent (delete-then-create, `make`-style targets are
  fine).

## Deliverable 1 — the runner

```
/app/run_pipeline.sh <workflow.yml> <rundir> [--workspace <dir>]
                    [--ref <ref>] [--event <event>] [--sha <sha>]
```

- `<workflow.yml>` — path to a workflow file to execute.
- `<rundir>` — output directory (created if missing). The runner clears and
  recreates `<rundir>/jobs` and `<rundir>/logs` at the start of every run.
- `--workspace <dir>` — the "repository" the workflow belongs to. Default: the
  directory containing `<workflow.yml>`. Must exist.
- `--ref`, `--event`, `--sha` — the `github.ref`, `github.event_name`,
  `github.sha` values visible to the workflow. Defaults: `refs/heads/main`,
  `push`, and a 40-`0` SHA.

**Exit codes.** Job failures are *data*, not runner errors: the runner executes
the whole pipeline, records failures in the summary, and still exits `0`. The
runner exits non-zero only on runner-level errors:

| code | meaning |
|---|---|
| 0 | pipeline fully executed; summary written |
| 1 | usage error |
| 2 | workflow unreadable / invalid YAML / violates the subset below |
| 3 | dependency cycle among jobs (or a `needs:` on an unknown job) |
| 4 | expression error (syntax or unknown function) |

On a non-zero exit no summary is written; a diagnostic goes to stderr.

**Output layout.** After a run:

```
<rundir>/summary.json                 the machine-readable summary (below)
<rundir>/jobs/<job-id>/               per-job working directory ("artifacts")
<rundir>/logs/<job-id>/step-<NN>-...  per-step stdout+stderr
```

### Step execution

- Every job gets a fresh, empty working directory `<rundir>/jobs/<job-id>/`.
  Steps run with that as their current directory, so relative paths in a step
  are private to the job. Nothing is pre-copied in.
- `$GITHUB_WORKSPACE` is exported to point at the workspace directory. Steps
  read (and write) shared repository files there; it is the only sanctioned
  way for jobs to pass files to one another.
- Each step's `run:` text is executed as:
  `bash --noprofile --norc -eo pipefail -c "<run>"` — a **clean shell per
  step** (no shell state carries between steps), with the inherited
  environment plus `GITHUB_WORKSPACE`, `GITHUB_JOB`, `GITHUB_REF`,
  `GITHUB_EVENT_NAME`, `GITHUB_SHA`, and the step's own `env:` (literal scalar
  values). Step stdout and stderr go to the per-step log. A non-zero exit
  makes the step **fail**.

### Workflow subset (the runner must support exactly this)

Top-level: any keys besides `jobs` are ignored (`name`, `on`, …). Each job
supports `name` (display only), `needs` (string or list), `if`, `outputs`,
`steps`; the keys `runs-on`, `timeout-minutes`, `permissions`, `concurrency`,
`strategy`, `env`, `container` are accepted and ignored. Any *other* job or
step key is a validation error (exit 2). Each step supports `id`, `name`,
`if`, `run` (required, non-empty), `env` (mapping of literals).

**Semantics.** Jobs run in a **topological order** that respects `needs:`
(ties broken by declaration order — the order the jobs appear in the YAML).
Then, for each job in that order:

- Evaluate the job-level `if:` expression; the default is `success()`.
  - `success()` — every direct `needs:` job has status `success`.
  - `failure()` — at least one direct need has status `failure`.
  - `always()` — true; `cancelled()` — false (a local run is never cancelled).
- If the condition is false the job is **skipped**: status `skipped`,
  `skip_reason` is `needs` when any direct need has status `failure` or
  `skipped`, else `if`; its steps are not run and its record lists no steps.
- Otherwise the job runs. For each step in order: evaluate the step `if:`
  (default `success()`, which here means "no earlier step in this job
  failed"; `failure()` means "an earlier step failed"; `always()`/`cancelled()`
  as above). A false condition skips the step. A failing step marks its job
  failed; subsequent steps are skipped unless their `if:` is true under the
  failed state.
- A job's status is `failure` if any step failed, else `success`.
- `outputs:` of a job is a mapping of literal expressions evaluated **only
  when the job succeeded** (failed/skipped jobs record `outputs: {}`). Their
  values are available to dependents as `needs.<job>.outputs.<key>`; an
  undefined output evaluates to `null`.

### Expression language (the exact subset)

Literals: `true`, `false`, `null`, integers, floats, strings `'…'` and
`"…"` (single-quoted strings double a `'` to escape it; double-quoted strings
support `\"`, `\\`, `\n`, `\r`, `\t`).
Functions: `success()`, `failure()`, `always()`, `cancelled()`,
`contains(haystack, needle)`, `startsWith(str, prefix)`, `endsWith(str, suffix)`.
Operators, tightest first: `!`, then `<` `<=` `>` `>=`, then `==` `!=`, then
`&&`, then `||`, then ternary `cond ? a : b`; parentheses group. Truthiness:
`false`, `0`, `null`, `""` and `''` are falsy.
Contexts: `needs.<job>.result` / `needs.<job>.outputs.<key>` (only for this
job's **direct** needs; anything else, including a missing job or key, is
`null`), `github.ref`, `github.event_name`, `github.sha`.
Write `if:` expressions as quoted YAML strings. Any other function name or a
syntax error aborts the run with exit 4.

### Summary schema (exact)

`<rundir>/summary.json`, one JSON object:

```json
{
  "workflow": "<basename of the workflow file>",
  "order": ["job-a", "job-b", "..."],
  "jobs": {
    "job-a": {
      "needs": ["..."],
      "status": "success | failure | skipped",
      "skip_reason": null | "needs" | "if",
      "outputs": {"key": "value"},
      "steps": [
        {"index": 1, "id": null | "<id>", "name": null | "<name>",
         "status": "success | failure | skipped",
         "exit_code": 0 | null}
      ]
    }
  }
}
```

`order` lists **every** job (skipped ones too) in topological order.
`id`/`name` are the values from the YAML, or `null` when absent. `exit_code`
is the step's exit status, or `null` when skipped. Skipped jobs have
`steps: []` and `outputs: {}`.

## Deliverable 2 — the workflow

`/app/.github/workflows/ci.yml` must use only the subset above and must:

- declare **at least three jobs**, some of them linked by `needs:` (a real
  dependency graph, not three independent jobs);
- give every job at least one `run:` step that does something real against the
  shipped repository (lint, test, build, package — via `make`, `pytest`, or
  `python -m yoke …`);
- run to completion cleanly under your own runner (exit 0, every job
  successful); use job-level or step-level `if:` conditions where they make
  sense for a CI pipeline.

## Constraints

- Work only under `/app`. Never read or write `/tests`.
- Do not hard-code the visible workflow's own file names or this repository's
  layout into the runner; hidden fixtures use different names and graph shapes.
- The verifier executes `/app/run_pipeline.sh` literally — it must exist, be
  executable, and take exactly the CLI above.
- Job failures recorded in the summary must not make the runner exit
  non-zero — only runner-level errors may.

## How you will be graded

Against the visible workflow: the runner exits 0, the summary's `order` is a
valid topological order of the delivered workflow's own graph, skip reasons
are consistent with `needs:` results, and at least one job actually executes
steps. Against the three hidden fixtures: the summary JSON must match the
expected output **exactly** (job order, every status, every skip reason,
every output, every step result and exit code), and the files the fixture
steps were designed to write must exist with the exact expected contents — so
your runner must genuinely execute steps in isolated per-job directories
under `<rundir>/jobs/`, with `$GITHUB_WORKSPACE` pointing at the fixture's
workspace.