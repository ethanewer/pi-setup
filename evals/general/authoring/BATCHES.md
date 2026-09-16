# Controlled batch generation

`tools/generate_tasks.py` gives all three lanes the same durable queue and trusted
QA entry point. It does not promote drafts or replace the release gates.

After `work`, use `qualify --reference-root /absolute/qa-reference --max-jobs 3
--workers 3 --trials 2` for the common QA workflow. It runs independent design
review first, skips repeat controls and pilots for revision-needed candidates,
then collects repeat runtime and blind-pilot evidence for passing designs. One
batch contamination audit follows. Its maximum reviewer/pilot calls are
`max-jobs × (1 + trials)`; it makes no author calls. Nonzero exit means candidates
are held or a check failed, not necessarily a runner crash. A successful command
means evidence was collected, **not** release acceptance. Mutations and substantive
release adjudication remain required. The subcommands below permit diagnostics
and rerunning individual stages. QA subcommands are explicit invocations; durable
lease recovery currently covers author workers, not a distributed QA scheduler.

```sh
python3 tools/generate_tasks.py --db /absolute/batch/queue.db enqueue \
  --csv /absolute/libraries_frameworks_github.csv \
  --lane skills --repository https://github.com/pallets/click
python3 tools/generate_tasks.py --db /absolute/batch/queue.db work \
  --workers 3 --max-jobs 3 --timeout 1200 --runtime
python3 tools/generate_tasks.py --db /absolute/batch/queue.db report
python3 tools/generate_tasks.py --db /absolute/batch/queue.db review --job JOB_ID
python3 tools/generate_tasks.py --db /absolute/batch/queue.db pilot --job JOB_ID --timeout 600
python3 tools/generate_tasks.py --db /absolute/batch/queue.db verify /absolute/batch/runs/JOB_ID/ATTEMPT_TOKEN
python3 tools/generate_tasks.py --db /absolute/batch/queue.db export --output /absolute/evidence-snapshot
python3 tools/generate_tasks.py --db /absolute/batch/queue.db verify-export /absolute/evidence-snapshot
```

Use a dedicated batch directory outside the live suite. Enqueue additional sources
with `repo` and `pr-issue`; the CSV is an allowlist, not a statement that every
listed repository is suitable. Each enqueue retains the CSV hash and selected row.
Repository URLs are normalized and unique across lanes within a queue. PR selection
still requires author inspection and independent source review.

After inspecting a failed draft, `retry --job JOB_ID` authorizes exactly one extra
authoring attempt, up to five total, and records that operator decision. A fresh
`work` invocation consumes it. For an unchanged draft affected only by QA tooling
or infrastructure, `recheck --job JOB_ID` reruns the shared runtime checks without
calling the author model. Neither operation erases previous failures.

## Operational guarantees

- Every generation and independent design-review call uses Codex CLI
  `gpt-5.6-luna` with `model_reasoning_effort="medium"`; no model override exists.
  The recorded session context must confirm those settings. Exports retain the
  minimal model/effort records, not unrelated session configuration.
- Queue identity fields and the selected repository are normalized mechanically;
  supplied conflicting identities are rejected. The raw candidate is retained.
- SQLite WAL and transactional claims permit multiple local workers. Heartbeats
  renew two-minute leases; stale workers cannot commit results. An expired attempt
  counts against its job's bounded retry allowance. Restart `work` to recover it.
- `--max-jobs` bounds author calls for that invocation, including retries;
  `--workers` bounds its concurrency (1–4). These are per invocation, not a global
  cross-process budget. Each author call has a wall-clock deadline. Timed-out local
  process groups are killed. Interrupted provider calls may still be billable.
- Retries use new directories and new sessions, carrying draft files and bounded
  QA feedback forward. Existing tasks and registrations are never overwritten.
- Trusted host QA scripts inspect the isolated suite via `--suite-root`; author
  edits cannot change those scripts. Static-only and runtime-only results are drafts.
- Source receipts must exist; skills must resolve inside the workspace and match
  their recorded SHA256. Design review must assess their substantive validity.
- Instruction five-word-shingle similarity checks compare against existing tasks
  and completed pending drafts. This catches close copies, not semantic duplicates;
  simultaneously finishing drafts still require a batch-wide diversity review.
- Every completed attempt has a content/permission seal pinned in the queue ledger.
  `verify` detects changed, added, removed and symlinked evidence. This is integrity
  checking, not a signature: protect the ledger from the authors and retain it with
  the bundles. Do not move a batch without migrating its absolute paths.
- Export copies sealed evidence, not scratch virtualenvs/checkouts, into a portable
  snapshot with an integrity index. Retain that index in trusted storage. Failed
  attempts without a completed seal remain listed in the report; they are not
  represented as sealed bundles.
- `report` includes every attempt, outcome, reviewer result and completed-turn token
  usage. Failed and interrupted calls are not silently treated as free. Dollar
  costs are not inferred without authoritative configured pricing.

## Isolation and release boundary

Author workspaces contain only the lane contract, selected source and generated
files. No existing task packages or QA reference corpora are supplied. Codex uses
workspace-write with network enabled for public source retrieval; this restricts
writes, **not host reads**. A dedicated host/container with restricted credentials,
read access, storage and egress is required for untrusted unattended production.
Read-only independent review receives the candidate, package, skills and receipts,
not the author conversation. It maps each exact acceptance criterion to tests and
records gaps in a fresh session. It cannot clear the task for release.

`pilot` starts a fresh offline container, supplies only the task instruction to a
fresh model session, and introduces hidden tests after that session ends. Each
invocation is one trial; run at least twice for initial calibration and retain
failures as well as successes. It records image identity, reward, available
deliverables, usage and session logs. The host CLI needs Docker access and currently
runs without a host sandbox, so the production isolation requirement above is
especially important. Prompt restrictions are not a security boundary. A single
successful pilot is not a validated difficulty label.

State is `queued → running → needs_review` or `failed`; a bounded failed attempt
may return to `queued`. There is deliberately no worker transition to `accepted`.
Complete the [shared QA gates](../qa/README.md), including negative mutations,
repeatability, blind pilots and contamination clearance, before additive
registration. Runtime pass rate is not acceptance yield or difficulty calibration.

The next scale qualification is a balanced 24-candidate experiment, eight per
lane, after the three-lane queue smoke test succeeds. Report draft and acceptance
yield separately, retries, token usage, elapsed time, failure classes and manual
review effort. Do not expand concurrency merely to compensate for low QA yield.
