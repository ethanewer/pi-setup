# Controlled batch generation

`tools/generate_tasks.py` gives all three lanes the same campaign-wide SQLite
coordinator and trusted QA entry point. Keep its database and WAL on one local
coordinating host, never a network filesystem. Candidate IDs are immutable and
separate from task IDs; distinct approved workflows may reuse a repository while
duplicate rejections remain in the ledger.

Freeze the existing tasks, registrations, and drafts, then validate the approved
source inventory before admission:

```sh
python3 tools/campaign_inventory.py freeze --output /absolute/campaign/baseline.json
python3 tools/campaign_inventory.py sources /absolute/campaign/source-identities.json \
  --output /absolute/campaign/diversity.json
```

The inventory command requires at least 200 canonical repositories. Identity JSON
follows `source-identity.example.json` and includes a pinned revision, structured
workflow, diversity labels, and an issue or skill identity where applicable.

Configure immutable limits and an independently approved isolation attestation
before paid calls. The receipt attests disposable workers, scoped credentials,
bounded storage, restricted host reads, controlled egress, and no shared-host
Docker daemon.

```sh
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db configure \
  --dollar-cap DOLLARS --author-calls CALLS --reviewer-calls CALLS \
  --pilot-calls CALLS --fleet-concurrency 3 --storage-bytes BYTES \
  --approved-by PERSON --policy-version POLICY --isolation-receipt isolation.json
```

After `work`, use `qualify --reference-root /absolute/qa-reference --max-jobs 3
--workers 3 --trials 2 --review-reserve-dollars MAX --pilot-reserve-dollars MAX`
inside the attested worker for the common QA workflow. It runs independent design
review first, skips repeat controls and pilots for revision-needed candidates,
then mutations, repeat runtime, and blind-pilot evidence for passing designs. One
batch contamination audit follows. Its maximum reviewer/pilot calls are
`max-jobs × (1 + trials)`; it makes no author calls. Nonzero exit means candidates
are held or a check failed, not necessarily a runner crash. A successful command
means evidence was collected, **not** release acceptance. Substantive
release adjudication remains required. The subcommands below permit diagnostics
and rerunning individual stages. All stages use the durable fenced scheduler.

```sh
python3 tools/generate_tasks.py --db /absolute/batch/queue.db enqueue \
  --csv /absolute/libraries_frameworks_github.csv \
  --lane skills --repository https://github.com/pallets/click \
  --identity /absolute/campaign/click-workflow-01.json --task-id OPAQUE-TASK-ID
GENERAL_ISOLATED_WORKER=1 python3 tools/generate_tasks.py --db /absolute/batch/queue.db work \
  --workers 3 --max-jobs 3 --timeout 1200 --runtime --reserve-dollars MAX_PER_CALL
python3 tools/generate_tasks.py --db /absolute/batch/queue.db report
GENERAL_ISOLATED_WORKER=1 python3 tools/generate_tasks.py --db /absolute/batch/queue.db review --job JOB_ID --reserve-dollars MAX
GENERAL_ISOLATED_WORKER=1 python3 tools/generate_tasks.py --db /absolute/batch/queue.db pilot --job JOB_ID --timeout 600 --reserve-dollars MAX
python3 tools/generate_tasks.py --db /absolute/batch/queue.db verify /absolute/batch/runs/JOB_ID/ATTEMPT_TOKEN
python3 tools/generate_tasks.py --db /absolute/batch/queue.db export --output /absolute/evidence-snapshot
python3 tools/generate_tasks.py --db /absolute/batch/queue.db verify-export /absolute/evidence-snapshot
```

Use a dedicated batch directory outside the live suite. Enqueue additional sources
with `repo` and `pr-issue`; the CSV is an allowlist, not a statement that every
listed repository is suitable. Each enqueue retains the CSV hash and selected row.
Repository URLs are normalized; source/workflow hashes, rather than repository
URLs alone, define uniqueness. PR selection still requires author inspection and
independent source review.

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
- SQLite WAL and transactional claims permit multiple local workers. Fenced stage
  records cover authoring, reviews, builds, mutations, repeat runtime, pilots,
  audits, and promotion; stale workers cannot commit results.
- `--max-jobs` and `--workers` still bound one invocation. The coordinator also
  enforces fleet-wide concurrency, call, dollar, and durable-storage reservations
  across processes. Reservation happens before each paid call; killed or uncertain
  calls retain their conservative reservation.
- Retries use new directories and new sessions, carrying draft files and bounded
  QA feedback forward. Existing tasks and registrations are never overwritten.
- Trusted host QA scripts inspect the isolated suite via `--suite-root`; author
  edits cannot change those scripts. Static-only and runtime-only results are drafts.
- Source receipts must exist; skills must resolve inside the workspace and match
  their recorded SHA256. Design review must assess their substantive validity.
- Instruction shingle checks remain an advisory late check. Admission additionally
  compares declared outcomes, decisions, deliverables, failure modes, skill
  coverage, and test structure, catching renamed workflows before a model call.
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
files. Production commands fail unless the launcher attests that they are inside
a disposable worker. `GENERAL_ISOLATED_WORKER=1` is a launcher assertion, not a
sandbox; never set it on an ordinary shared host.
Read-only independent review receives the candidate, package, skills and receipts,
not the author conversation. It maps each exact acceptance criterion to tests and
records gaps in a fresh session. It cannot clear the task for release.

`pilot` starts a fresh offline container, supplies only the task instruction to a
fresh model session, and introduces hidden tests after that session ends. Each
invocation is one trial; run at least twice for initial calibration and retain
failures as well as successes. It records image identity, reward, available
deliverables, usage and session logs. Docker access exists only inside the
attested disposable worker; it must not expose a shared-host daemon. Prompt
restrictions are not a security boundary. A single
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

Qualification now runs three distinct semantic wrong-solution controls before
repeat runtime and pilots. Each mutation must produce reward 0 and the declared
behavioral diagnostic. Final promotion is fingerprint- and QA-policy-bound,
independently approved, exclusively serialized, and idempotent:

```sh
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db promote \
  --candidate-id CANDIDATE --fingerprint SHA256 --policy-version POLICY \
  --approval approval.json --manifest /absolute/campaign/release-manifest.json
```

This updates the protected campaign manifest; it does not copy into the live
suite. After portable-export and clean-checkout verification, install the exact
package and use `register_task_wave.py`. Registration takes an exclusive lock and
is additive. At release completion, verify the frozen baseline with
`campaign_inventory.py verify`; baseline paths must remain unchanged.
