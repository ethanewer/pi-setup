# Three-lane batch qualification — 2026-09-15

## Outcome

The three authoring lanes now have a bounded queue and a common QA orchestration
command. The controlled run exercised new sources through generation, repairs,
runtime checks, independent design review, blind pilots and contamination QA.
**All three candidates remain held for design revisions; none was registered.**
Existing task packages and registry entries were not changed in this phase.

| Lane | New source | Author calls | Final oracle / baseline | Blind pilots | Design review |
| --- | --- | ---: | --- | --- | --- |
| Skills | Click; new `click-manifest-auditing` skill | 4 | 1 / 0, twice | 2 / 2 passed | Revise |
| Repository | Jinja | 2 | 1 / 0, twice | 2 / 2 passed | Revise |
| PR/issue | HTTPX PR 3364 | 5 | 1 / 0, twice | 2 / 2 passed | Revise |

The source CSV was the user-provided `libraries_frameworks_github.csv`; its hash
and selected rows are retained in [source receipts](evidence/sources).
The skill-creator guidance informed the reusable skill workflow and frontmatter;
the Click skill passed the bundled skill validator. Skill references are checked
against their actual content hashes by the worker.

## Infrastructure delivered

- Transactional SQLite claims, heartbeat leases, stale-worker fencing, bounded
  attempts, process deadlines and explicitly recorded repair authorizations.
- Codex CLI generation pinned to `gpt-5.6-luna`, medium reasoning. All **23** model
  sessions in this experiment—11 author calls, 6 reviews and 6 pilots—have matching
  recorded model/effort contexts in the export.
- Queue-owned identity normalization, CSV allowlisting, per-batch repository
  deduplication, skill hashing and instruction-similarity checks.
- Trusted shared QA against isolated draft roots, offline oracle/baseline
  containers, scoped cleanup, independent criterion-to-test reviews and blind
  pilots that receive tests only after the solving session finishes.
- Portable evidence seals anchored in the queue ledger, usage accounting,
  separate rechecks without reauthoring, and an explicit qualification command.
  Qualification skips expensive pilot work when design review requests revision.
- **30 passing tests** across authoring, queue/orchestration, pilot transport and
  contamination-audit helpers. The composed qualification command was also run
  live on HTTPX: it held the candidate at design review, skipped new pilots and
  retained its audit and qualification evidence.

See [batch operations](../../authoring/BATCHES.md) for commands and limitations.

## What the experiment exposed

Initially, 0/3 candidates reached the draft handoff. Failures included a missing
source field, wrong grader mount paths, tests copied into an image, inverted
rewards, import-path errors and an invalid assertion about upstream headers.
An initial evidence-sealing implementation also incorrectly included scratch
virtualenv symlinks; the revised implementation excludes scratch while still
rejecting symlinks in task/evidence files. These failures were retained, not erased.
Local advisory checks, clearer reward/mount contracts, mechanical normalization,
more useful repair feedback and a QA-only recheck path were added in response.

Runtime success is not acceptance. Review holds include incomplete malformed-record,
path and failure-output coverage for the skills task; an explicitly promised but
unenforced upstream regression suite for Jinja; and provenance/difficulty concerns
for HTTPX. Some reviewer claims were inaccurate: the first Jinja review misread
the normalized sort key, and claims of unbounded verification overlook the shared
backend's timeout defaults. Updated reviews receive runtime evidence and clearer
harness context. All review outputs remain available for adjudication; their
claims are not automatically treated as established facts.

Two successful pilots per task are a transport/solvability smoke test, not a
statistically meaningful difficulty calibration. Missing semantic mutation tests
and unresolved review findings still block release.

## Contamination QA

The three-candidate audit was clear, with no unresolved flagged pairs. The live
qualification command also audited its selected HTTPX candidate successfully.
Terminal-Bench was accessed only by this QA audit, never supplied to authoring
contexts. Reference identity, fingerprints and audit outputs are preserved.
Clearance against this frozen reference does not establish universal originality.

## Accounting and readiness

The run used 11 author calls (8 repairs beyond the initial three), 6 review calls
and 6 blind-pilot calls. Recorded aggregate usage was 10,265,176 input tokens,
including 9,504,333 cached tokens, and 166,923 output tokens. Additional cache-write
and reasoning counters are retained separately in the machine-readable report;
do not add overlapping counters together. No dollar cost is asserted without
configured pricing. First author claim to final initial-QA completion took about
600 seconds with concurrent execution; subsequent review/pilot/audit work is extra.

The 24-candidate expansion was **not run**. The appropriate next step is to improve
coverage/provenance and adjudication quality, then measure acceptance yield—not
just draft yield—on eight candidates per lane. The current implementation supports
controlled local batches; unattended scale still needs dedicated author/pilot
isolation, cross-process budget enforcement and a resumable distributed QA-stage
scheduler. Workspace-write does not prevent host reads, and pilot Docker access
currently requires an unsandboxed host CLI. Do not treat prompts as isolation.

## Evidence

[Machine-readable report](evidence/report.json), [bundle index](evidence/index.json),
and [recorded model settings](evidence/session-contexts.json) cover 30 sealed
bundles. The first Jinja attempt failed before sealing; its failure remains in
the ledger, and its author event stream and unchanged package were captured by
the subsequent QA recheck. Disposable checkouts/virtualenvs are not exported.

Snapshot seal SHA256:
`608d26c4e34ea4f5aec4803ddaf4f87bb3d2417c8234a89d568178529b0fe03f`

Verify from the general suite directory:

```sh
# Git preserves executable bits but not group-write bits. Restore the captured
# 0664 modes on these two pilot outputs before checking the original seals.
chmod 664 qa/scale-2026-09-15/evidence/pilots/pr-issue-c9226c2ff37a/232e572cedec4681ae6c05353c6e9e2f/deliverable-0
chmod 664 qa/scale-2026-09-15/evidence/pilots/pr-issue-c9226c2ff37a/560169ac849042c387cb4a60741803c9/deliverable-0
python3 tools/generate_tasks.py --db /tmp/general-scale.U9t4EQ/queue.db \
  verify-export qa/scale-2026-09-15/evidence
```

The portable snapshot does not depend on the live queue for verification; an
otherwise empty local database path also works. The original queue and scratch
artifacts remain at `/tmp/general-scale.U9t4EQ`; the durable evidence is here.
