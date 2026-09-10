# hopper-ledge — repair the team's CI pipeline

The repository at **`/app/repo`** belongs to the ledger-registry team. The org
runs its CI on a small local runner instead of a hosted service: the script at
**`/app/repo/ci/runner.py`** executes the pipeline defined in
**`/app/repo/ci/pipeline.json`** directly on the machine, running each job's
steps in a shell, honouring `needs:` and per-step gating, exchanging files
between jobs through an artifact store, and keeping a dependency cache so warm
runs skip the install step. The same runner is shared by several repositories
in the org.

The pipeline is currently **red**. It fails for three independent reasons, and
the failures only appear when the pipeline runs as a whole: every individual
job, and every individual test script, works fine on its own. Your job is to
repair the repository so the pipeline is green and stays green across
consecutive runs.

## The environment

- Python 3.12 with pytest 9.1.1 installed; no network. Everything you need is
  already on disk.
- `/app/repo` is a git repository with history. `README.md` there explains the
  layout and the documented way to run the pipeline. The files the pipeline
  invokes (`ci/pipeline.json`, scripts under `ci/`, `scripts/`, the suite under
  `tests/`, the source under `src/`) are all on disk.
- Do not modify anything outside `/app/repo`. Do not add, remove or change the
  pipeline's network access (there is none).

## The delivery contract

Your repair must make **`/app/repo`** green under the documented invocation:

```
python3 /app/repo/ci/runner.py --pipeline /app/repo/ci/pipeline.json \
    --repo /app/repo --work-root <WORK> --cache-dir <CACHE> \
    --summary <SUMMARY>
```

The runner exits **0 exactly when every job's steps succeed**, and always writes
`<SUMMARY>` as JSON with this shape:

```json
{
  "result": "success" | "failure",
  "failed_job": null | "<job name>",
  "jobs": { "<job name>": { "status": "success" | "failure",
             "steps": [ {"name": "...", "status": "done"|"skipped"|"failed",
                         "output": "..."} ],
             "cache": [ {"key": "...", "path": "...", "hit": true|false} ] } },
  "tests": { "collected": <int|null>, "passed": <int|null> }
}
```

All four conditions below must hold:

1. **Cold run green.** With a fresh `<WORK>` and an empty `<CACHE>`, the command
   above exits 0. The dependency restore reports a cache **miss** and the
   install step runs: in the summary, that step's status is `done` and the
   cache events show `"hit": false` for the first run.
2. **Warm run green.** Immediately after, with a fresh `<WORK>` but the same
   `<CACHE>`, the command exits 0 again. This time the restore reports a cache
   **hit** and the install step is **skipped** (status `skipped` in the
   summary): the dependency cache saved by the cold run is complete and
   reusable, so warm runs must not re-install.
3. **Checkout hygiene.** After either run, the working tree at `/app/repo`
   contains no generated build or dependency output (nothing like `dist/`,
   `.deps/`). Pipeline output belongs in `<WORK>`/`<CACHE>`, never in the
   checkout.
4. **The suite stays intact.** Do not delete, weaken, skip, reorder, or filter
   any test and do not change any assertion in `/app/repo/tests` — no
   `pytest.mark.skip` / `pytest.mark.skipif` / `pytest.skip(...)` / `xfail`, no
   `--deselect`, no `-k` filtering, no edited expected values. The pipeline's
   artifact gate (the test job's `verify_artifact` step) must run and pass on
   every run, and every test in the suite must be collected and pass every run.

## Notes for getting it right

- The pipeline's own summary and stdout tell you which step fails and what it
  prints; the failures are deterministic and reproduce every time. The three
  defects are independent: masking one leaves another visible, and the warm
  run only exists to expose one of them.
- The runner is **shared across the org**. After your repair the verifier runs
  `/app/repo/ci/runner.py` against three other repositories with different job
  names, artifact directories, cache paths, dependency lockfiles, and job
  graphs (including a three-job chain). Your fix must therefore live in the
  shared machinery and take its behaviour from the pipeline definition — do
  not hard-code anything specific to this repository (paths, job names, or
  package names), or it will break the other repositories.
- You may create new files under `/app/repo` (new scripts, documentation) as
  long as the four conditions above hold. You may not delete existing files
  except scratch output you generated yourself.