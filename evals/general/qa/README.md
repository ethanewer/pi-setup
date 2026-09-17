# Shared QA backend

All three front ends use identical acceptance gates. No source gets an exemption.
Use `--runtime-only` to run static checks and oracle/nop controls before independent
review. This produces a draft report and never grants acceptance. Keep the logs as
review evidence; the final acceptance run repeats the controls after review.
For tasks declaring `network_mode = "no-network"`, use `--runtime-backend docker`
when Harbor's installed Docker provider cannot enforce that policy. This backend
builds the same task image, runs fresh oracle/nop containers with `--network none`,
enforces the declared CPU/memory budgets, mounts grader files read-only, and records
the image identity and logs. It never relaxes the task's network policy.
Static-only runs are drafts. Missing tools, failed commands, absent evidence,
stale fingerprints, and missing rewards block acceptance.

Campaign candidates also provide `tests/mutations/manifest.json` with at least
three distinct mutation kinds and scripts. Each script installs one plausible
incomplete or incorrect approach into a pristine container. The shared mutation
stage requires reward 0 and a diagnostic matching that case's `intended_reason`;
syntax errors, missing files, and duplicate scripts do not establish semantic
coverage. Independent review still decides whether the selected mutations cover
the important requirements and plausible shortcuts.

Run `python3 tools/qa_task.py --candidate PATH --static-only` to obtain the package
fingerprint and task-scoped layout and binary-reward checks. Reviewers then record
the following gates, with a reviewer identity different from the candidate author,
`status: "pass"`, and concrete `evidence` paths or detailed observations:

| Gate | Required evidence |
| --- | --- |
| source | Original source receipts, license, immutable revisions, no benchmark-derived authoring material |
| behavior | Every acceptance criterion tested; oracle solves the stated problem; hidden cases test generalization |
| isolation | No oracle, hidden expected outputs, fix history, or answer-bearing artifacts accessible to agent |
| negative_controls | Untouched baseline and plausible incorrect/incomplete repairs fail for the intended reason |
| reproducibility | Two fresh runs agree; pinned dependencies, offline execution, CPU/thread limits, time and image size checked |
| contamination | Reference identity, content audit, similarity triage, and resolution of every flagged match |
| difficulty | Complete ten-dimension rubric, measured oracle time, realistic budget, pilot evidence and observed failure causes |
| diversity | Duplicate search against existing tasks and pending candidates; practical skill/domain contribution |

Review JSON has a top-level `fingerprint` and one object per gate above. Example
gate: `"behavior": {"status": "pass", "reviewer": "reviewer-id", "evidence": "qa/reviews/my-task/behavior.md"}`.
Evidence must be durable and reviewable. The backend checks the review contract;
human release review checks the evidence's substantive validity.

Then run:

```sh
python3 tools/qa_task.py --candidate authoring/candidates/my-task.json --review qa/reviews/my-task.json
```

The backend reruns static checks and runs Harbor oracle and nop in unique job
directories. Both commands must succeed; oracle must write exactly one reward of
1 (or 1.0), and nop exactly one reward of 0 (or 0.0). Logs and a machine-readable
report are retained under `qa/results/`. Acceptance is tied to the unchanged
package fingerprint. These runtime controls supplement the independent review;
they do not prove resistance to all verifier exploits.

## Contamination QA

For sealed batch drafts, run `python3 tools/generate_tasks.py --db /absolute/batch/queue.db audit --reference-root /absolute/reference-checkout`.
This snapshots all QA-checked candidates and records results in the batch's QA
evidence, never in author workspaces. `qa/audit_candidates.py` also accepts one
`--suite-root` for all candidates or one per candidate in matching order. Flags
remain unresolved until independently reviewed; no audit command promotes tasks.

Terminal-Bench is used only as a contamination reference, never as an authoring
source or coverage target. Keep reference access and audit output in QA, outside
authoring contexts and task images. Use `tools/freeze_reference.py --verify`,
`tools/check_task_similarity.py`, `tools/check_upstream_disjointness.py`, and
`tools/audit_independence_stream.py` with the reference checkout and provenance.
Read each command's help before running; reference-dependent checks fail closed
when the checkout is missing. Resolve similarity flags with independent review
using `check_task_similarity.py --mode review --review-file PATH`. A successful
triage command alone is not clearance. Preserve reference version, commands,
reports, and reviewer decisions as contamination evidence. Existing frozen
reference specs support these checks only.

## Release

Check reward guards, numeric thread pins, git safe-directory handling, dependency
pins, tracked files, and image hygiene with the existing tools. Record these in
the reproducibility review. Register accepted candidates additively; do not
rebuild legacy coverage claims or reassign existing difficulty labels. Include
the QA report, candidate, review evidence, and exact release package identity in
release review. Existing tasks are preserved, including historical metadata;
this new contract applies to newly authored tasks.
