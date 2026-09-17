# Plan: generate and release 2,000 new general evaluation tasks

Date: 2026-09-16
Status: execution started; the first qualification round is paused after static authoring QA.

## Objective and fixed constraints

Deliver **2,000 newly authored, distinct, QA-accepted, additively registered tasks**.
Drafts, failed attempts, repairs, duplicate variants and held candidates do not
count toward that total. Preserve every existing task and its recorded metadata.
Freeze a baseline inventory of both registered tasks and existing drafts before
starting; the earlier pilot tasks are excluded from this campaign's new-task count.

Use Codex CLI **`gpt-5.6-luna` with medium reasoning** for all task generation,
skill generation and repairs. This interprets `glt-5.6-luna` in the request as a
typo for the model specified in the preceding work. Pin independent model reviews
and blind pilots to the same settings for a consistent initial experiment.
Do not silently substitute a model if the requested model is unavailable.

There are exactly three authoring front ends feeding one shared QA backend:

| Lane | Accepted-task target | Authoring input |
| --- | ---: | --- |
| Skills to task | 700 | New reusable, validated skills grounded in real library/framework workflows |
| Repository to task | 700 | Pinned repositories and original, bounded engineering objectives |
| PR/issue to task | 600 | Real upstream issues/PRs with verified before/after behavior |
| Total | **2,000** | No benchmark-derived authoring material |

The lane allocation is a planning target, not permission to lower standards.
Changing it requires a recorded campaign decision. Benchmarks must not supply
scenarios, objectives, source selection, solutions, tests or difficulty targets.

## Starting point

The [batch runner](BATCHES.md) supports leased author jobs, bounded repairs,
isolated drafts, shared runtime checks, independent reviews, blind pilots and
sealed evidence. The [latest smoke run](../qa/scale-2026-09-15/REPORT.md) produced
three drafts through 11 author calls. All passed repeated oracle/baseline checks,
six blind pilots passed, and the contamination audit cleared. Nevertheless,
all three were held for design revisions. The 24-candidate expansion has not run.

Therefore, do not extrapolate throughput from runtime passes or launch thousands
of jobs on the current implementation. Acceptance yield is not established.

## Progress snapshot — 2026-09-18

The campaign workspace is `/home/ee/general-task-campaign-2000`; it remains
outside the live suite and is intentionally not committed. Generation is stopped:
there are no author workers, proxy processes, or billable calls running.

- The supplied CSV was retained with SHA256
  `bfd194fac66fecc11bc53fab590db53f6991bb37b3187a113aabf23dd1d5da42`.
  Discovery verified 219 eligible, licensed repositories, clearing the 200-source
  inventory gate.
- The pre-campaign baseline records and hashes 17,564 task/candidate files and
  existing registry entries. Campaign identity, semantic admission, global
  budget/concurrency, stage fencing, sealed evidence, mutation, portable export,
  and idempotent promotion controls are implemented. The focused campaign and
  authoring suite passes 39 tests.
- Eight reusable skills were generated, validated, content-hashed, and sealed.
  Two source-planning batches produced eight repository workflows and eight
  PR/issue workflows with pinned revisions and receipts.
- The balanced qualification inventory contains 24 admitted candidates: eight
  skills, eight repository, and eight PR/issue candidates. Seven drafts have
  passed static package QA and are in `needs_review` (two skills, two repository,
  three PR/issue); the other 17 remain queued. No candidate has completed runtime
  QA, independent review, mutations, repeatability, pilots, contamination review,
  human adjudication, or promotion. Accepted progress is therefore **0 / 2,000**.
- Six interrupted calls retain conservative uncertain charges. Across 16 author
  reservations, the ledger currently accounts for `$19.87` against the approved
  `$100.00` qualification cap; historical reservations total `$41.50`. The
  campaign occupies about 671 MB.
- Live qualification exposed and fixed two coordinator defects: nested build
  stages now share their candidate's fleet slot, and storage accounting tolerates
  nested scratch directories disappearing during traversal. One unchanged draft
  was resumed through static QA without paying to reauthor. Long-context pricing
  corrections are recorded as audited operator events.

The next action is to resume the remaining 17 author jobs at concurrency three,
then execute the shared runtime and review gates for all viable drafts. Do not
begin the 120-candidate validation batch until this 24-candidate round produces at
least four fully accepted tasks per lane with zero unresolved critical defects.
No completion-date or full-campaign budget projection is yet justified because
the measured final acceptance yield remains zero.

## Phase 0 — remove blockers before campaign generation

Engineering owner: implement and test the following; QA owner: approve the gates.
One person may operate both roles, but authors must not self-approve their tasks.

1. **Fix source and task identity.** The current queue allows one job per
   repository and derives the task ID from lane plus repository. It cannot safely
   produce multiple objectives from the same repository, even across batches.
   Introduce a campaign-wide immutable candidate ID and a separate source identity
   containing lane, canonical repository, pinned revision, issue/PR or skill hash,
   and an approved workflow specification. Keep repairs under the same candidate.
   Migrate existing queue data without changing existing task IDs or evidence.
   Test cross-batch collisions, duplicate admission and concurrent promotion.
2. **Build a global admission ledger.** Deduplicate source/workflow identities and
   compare objectives, instructions, skill coverage and test structure against
   existing tasks and all campaign candidates, including concurrent drafts.
   Lexical similarity alone is not sufficient. Retain rejected duplicates and
   their reasons so they are not repeatedly generated under new names.
3. **Isolate authors and pilots.** Use dedicated disposable workers with scoped
   credentials, bounded storage, restricted host reads and controlled egress.
   Authors cannot access existing task solutions, QA reference corpora, the
   release registry or the evidence ledger. Pilots cannot access grader files
   before evaluation. Remove dependence on an unsandboxed shared-host Docker CLI.
4. **Make every QA stage resumable.** Extend leases, fencing, heartbeats and
   attempt records to reviews, builds, mutations, pilots, audits and promotion.
   Record stage start before launching a billable call. Recover from killed
   workers without losing accounting or accepting a stale result. Use SQLite on
   one coordinating host initially; do not share its WAL over a network filesystem.
5. **Enforce global budgets.** Add a fleet-wide concurrency and spending admission
   controller, not merely per-command limits. Reserve budget before each call;
   account for retries, reviews, pilots, failed calls and uncertain charges.
   Interrupted calls are not assumed free. Pause when usage cannot be reconciled.
6. **Improve authoring contracts.** Require a criterion-to-test map, immutable
   source/skill receipts, captured baseline commands/results, pinned dependencies
   and explicit resource limits. Keep identity normalization mechanical. Expose
   advisory checks before handoff. Require 1 for correct work and 0 for baseline
   failure, use the actual grader mount path, and retain useful diagnostics.
7. **Strengthen substantive QA.** Add adversarial behavioral cases and semantic
   mutation controls, not just syntax checks and an untouched baseline. Every
   claimed broad compatibility guarantee must have executable coverage or be
   narrowed honestly. Validate reviewer allegations against artifacts and the
   harness; model reviews are fallible evidence, not release authority.
8. **Make evidence portable and promotion idempotent.** Preserve bytes, executable
   permissions and recorded source modes through export and checkout. Reject
   tampered/missing evidence. Bind every gate to the final fingerprint and version
   of the QA policy. Use exclusive promotion and additive registration; a retry
   cannot overwrite a task or count the same task twice.

Exit gate: unit/integration tests pass, worker-kill recovery is demonstrated for
every stage, isolation checks pass, and an independently inspected end-to-end
test proves that stale evidence and a deliberately incomplete solution cannot
be promoted. Reuse the previous held drafts only as diagnostic fixtures, not as
new campaign tasks.

## Phase 1 — source discovery and workflow inventory

Start with the supplied CSV:
`/Users/ethanewer/posttraining-2606/local/data/terminal_docs_v004/libraries_frameworks_github.csv`.
Retain its SHA256 and selected rows. Normalize URLs; remove duplicate aliases,
blank rows and unavailable sources. The CSV is a discovery seed, not evidence
that every repository is eligible or an unlimited supply of distinct tasks.

For each admitted source, record an immutable commit, license/reuse basis,
dependency/build requirements, baseline reproducibility and suitable workflows.
For issue/PR sources, capture the reference, pre-fix state, actual failing
reproduction and verified fix behavior. Reject unverifiable or answer-leaking
sources. Do not copy fix history into agent environments.

Develop an inventory covering at least 200 eligible repositories if maintaining
the proposed cap of 10 accepted tasks per repository across all lanes. Count
forks and aliases together. If the CSV cannot support this, request approval to
expand the source inventory; do not silently relax diversity or fabricate sources.
Also review concentration by ecosystem and task family, not repository count alone.

Each proposed workflow must name a real outcome, required decisions, observable
deliverables, relevant failure modes and how it differs from existing work.
Parameter substitutions or renamed copies are not distinct tasks. For the skills
lane, create and validate the reusable skill first, pin its content hash, and
record whether the skill is visible to the solving agent. Reusing a skill requires
a materially different workflow and fresh independent tests.

Before production, approve a diversity matrix spanning domains, languages,
workflows and difficulty. Proposed concentration limits: no single repository
above 10 tasks, no near-identical scenario family above 40, and no language above
45% of the release. Treat these as reviewable campaign constraints, not verified
properties of the current inventory. Difficulty must follow measured work;
straightforward local repairs may be easy. Do not inflate labels to fill quotas.

## Phase 2 — qualify generation quality before increasing volume

The following thresholds are proposed go/no-go criteria, not observed results.
Approve them before running the campaign and retain failures in their denominators.

| Stage | New candidates | Entry/exit criteria |
| --- | ---: | --- |
| Balanced qualification | 24: 8 per lane | Phase 0 complete; at least 4 accepted per lane, zero unresolved critical defects, full evidence for every acceptance |
| Validation batch | 120: 40 per lane | Qualification passes; at least 50% acceptance in each lane, median author calls per candidate at most 2, acceptable measured cost and review effort |
| Production waves | At most 100 candidates per wave initially | Two consecutive gate-passing batches; raise to at most 250 only after two production waves also pass |

Qualification and validation acceptances count toward the 2,000 only if they meet
the same final release policy. There is no separate lower-standard pilot category.
If a stage misses its gate, pause new admissions, classify the causes, fix the
system or reject unsuitable sources, and repeat qualification on fresh candidates.
Do not compensate for poor yield by raising concurrency.

Start with three concurrent author calls. Increase fleet-wide author concurrency
to six and then twelve only after qualifying the budget controller, worker
isolation, service limits and downstream capacity. The current CLI accepts only
1–4 workers per invocation; larger fleet limits require the planned coordinator,
not an unsupported `--workers 12` command. Bound QA concurrency independently and
stop author admissions when the review backlog exceeds one production wave.

## Shared QA backend and acceptance policy

All lanes pass exactly the same gates, in cost-aware order:

1. Admission and source/provenance validation; global duplicate/diversity check.
2. Static package checks, dependency/source pins, layout and answer-leak checks.
3. Fresh offline oracle and untouched-baseline controls; require rewards 1 and 0.
4. Independent design review mapping every criterion to concrete behavioral tests.
   Return actionable revisions or reject; do not spend on pilots for failed designs.
5. Semantic mutation testing: at least three applicable, distinct incomplete or
   incorrect approaches per task. Every mutation must fail for the intended
   behavioral reason. Cover omitted requirements and plausible shortcuts, not
   only missing files or syntax errors. Record any required policy exception.
6. Repeat runtime controls in fresh containers and verify that results agree.
7. At least two blind Luna/medium pilots per prospective acceptance. Pilot failure
   is not an automatic rejection of a valid hard task; diagnose ambiguity,
   infrastructure and capability separately. Oracle success remains mandatory.
   Use a stratified sample with additional trials for difficulty calibration;
   two trials alone do not establish a reliable pass-rate estimate.
8. Contamination QA: use Terminal-Bench only as a frozen QA reference. Keep its
   contents and audit output outside author contexts. Record reference identity,
   resolve every flagged match independently, and reject missing clearance.
9. Final source, diversity, difficulty and evidence adjudication; verify all gate
   fingerprints against the exact package to be registered.

Independent human release review is mandatory initially. An independent reviewer
must adjudicate each candidate's evidence; audit at least 10% of each wave in
additional depth, covering all lanes and high-risk sources, before releasing that
wave. Any critical defect holds the wave and triggers full inspection of the
affected family. Model agreement is not a substitute for these checks.

Do not lower acceptance requirements because the campaign is behind schedule.
The existing `qualify` command collects evidence but does not establish final
acceptance; complete the [shared QA release procedure](../qa/README.md).

## Repair, rejection and stop rules

- Initial allocation: one author call and at most two repair calls per candidate.
  Additional repairs require a recorded operator decision; never exceed the
  current hard ceiling of five author calls for one candidate.
- Repairs use fresh sessions and receive bounded, verified QA feedback. Preserve
  prior attempts. A content change invalidates earlier fingerprint-bound gates.
- Recheck unchanged content after infrastructure fixes without paying to reauthor.
  Do not repeatedly repair candidates with unsuitable scope, unclear licensing,
  untestable objectives or substantial duplication; reject them and admit others.
- Review false positives must be adjudicated, not blindly implemented. Track
  reviewer disagreement and revision effectiveness by lane and source family.
- Pause admissions for isolation failures, unknown spend, missing evidence,
  unrecoverable leases, unreconciled duplicates or release-integrity failures.
  Pause a lane if its latest completed wave falls below 50% acceptance or exceeds
  its approved cost/review-effort limits. Resume only after a documented remedy.

## Capacity, budget and completion accounting

Plan for **2,000 accepted tasks**, not 2,000 author calls. Candidate demand depends
on measured acceptance yield:

| Acceptance yield | Approximate candidates needed for 2,000 acceptances |
| --- | ---: |
| 80% | 2,500 |
| 60% | 3,334 |
| 50% | 4,000 |
| 40% | 5,000; below the proposed production gate |

These are planning expectations, not guarantees. Estimate separately by lane:
remaining candidates = ceiling(remaining lane target / measured lane yield).
Do not estimate from a lane with zero accepted tasks. Use conservative uncertainty
bounds once samples are available and update forecasts after every wave.

Proposed outer campaign cap: **6,000 candidate admissions and 18,000 author/repair
calls**, subject to a separately approved total spending cap. These are stop
limits, not budgets to consume. Reviews and pilots require separate reservations
under the same global spending cap. If the caps cannot deliver 2,000 accepted
tasks, stop and request revised scope or budget; never relabel drafts as accepted.

Before launch, the campaign owner must approve: dollar cap, per-stage token/cost
reservations, compute/storage cap, review-hours cap, fleet concurrency and the
first batch's spend allocation. Populate prices from the actual account's rates
at that time; this plan does not invent model prices or promise a calendar date.
The present CLI reports usage after calls, so its wall-time limit is not a hard
live token cap. Reserve conservatively and use provider-side limits where available.

Report authoring, repair, review, pilot, build and audit costs separately. Do not
double-count cached input, cache-write or reasoning counters. Track unknown
charges explicitly. Measure human adjudication time rather than assuming it is
free. Estimate duration from the slowest measured stage—authoring, runtime QA,
review or release—not from model generation throughput alone.

Stop admissions per lane when accepted tasks plus admitted work provide enough
coverage to finish its target. Near the target, shrink waves and choose releases
one candidate at a time. Extra valid candidates stay held as reserves; only 2,000
new unique IDs enter the campaign's final release manifest. Replace any withdrawn
campaign task before claiming completion, without touching pre-campaign tasks.

## Operational execution

Use a fresh campaign workspace outside the live suite, a protected coordinator
ledger, and immutable per-attempt artifact locations. Run the existing commands
below during qualification; the identity, global scheduling and budgeting changes
listed in Phase 0 must land before repository reuse or unattended production.

All model calls must include the equivalent of:

```sh
codex -a never exec --ignore-user-config \
  -m gpt-5.6-luna -c 'model_reasoning_effort="medium"' \
  --skip-git-repo-check --json -C /absolute/isolated/workspace -
```

The runner must supply the approved sandbox/network policy, prompt, output paths
and deadline. Verify recorded session model/effort, not just command-line intent.

Existing runner examples, from `evals/general`:

```sh
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db enqueue \
  --csv /absolute/libraries_frameworks_github.csv \
  --lane repo --repository https://github.com/OWNER/REPOSITORY --max-attempts 3
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db work \
  --workers 3 --max-jobs 24 --timeout 1200 --runtime
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db qualify \
  --reference-root /absolute/qa-reference --max-jobs 24 --workers 3 --trials 2
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db report
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db export \
  --output /absolute/evidence/wave-001
python3 tools/generate_tasks.py --db /absolute/campaign/queue.db verify-export \
  /absolute/evidence/wave-001
```

Replace placeholders with approved sources/paths; enqueue the full balanced
source list before running. `work --max-jobs` limits author invocations, including
repairs, so 24 invocations may not finish 24 candidates. Additional invocations
require remaining batch/campaign budget. `qualify --max-jobs` instead limits
selected draft candidates; nonzero exit may mean a legitimate QA hold.
These commands do not perform final promotion or registration.

## Wave report and release deliverables

For each wave, publish a machine-readable ledger and concise Markdown report:

- Admitted, rejected, held, accepted and registered counts by lane and source.
- First-pass acceptance and eventual acceptance yield, including all failures.
- Calls/repairs per candidate, stage latency, resource usage, dollar spend,
  cost per accepted task, review hours and unresolved accounting.
- Coverage/dedup decisions, mutation results, blind-pilot outcomes and calibrated
  difficulty uncertainty; unresolved findings must remain visible.
- Final fingerprints, source/skill hashes, QA policy version, session settings,
  immutable evidence references and independent approval records.

Release in additive, audited waves with exclusive task IDs. Verify the exported
artifact and a clean checkout before registration. Restore metadata that Git
cannot represent through a documented, verified packaging process. Keep large
scratch runs out of Git; retain durable evidence in approved immutable storage
with hashes and accessible pointers. The previously checked-in smoke evidence
does not imply that all 2,000 tasks' raw logs must be committed to this repository.

Completion requires exactly 700 skills, 700 repository and 600 PR/issue tasks
accepted and registered under the approved allocation; 2,000 unique final IDs;
complete reproducible evidence; no unresolved release-blocking findings; and a
baseline comparison proving existing task contents and labels were preserved.
Publish the final manifest, source/diversity inventory, difficulty report, full
cost/yield summary and reproduction instructions. Commit and push the approved
release changes only after those checks pass.
