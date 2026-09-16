# Common candidate contract

Each front end uses `tools/author_task.py` and emits schema version 1. The author
builds the task package; the command validates provenance and normalizes the
handoff. It does not claim to generate a correct environment or verifier.

For bounded multi-source runs, use the [durable batch queue](BATCHES.md). It
invokes the selected generation model and feeds all lanes to the same QA backend;
it never registers drafts automatically.

Example input for skills to task:

```json
{
  "task_id": "config-recovery",
  "author": "author-id",
  "objective": "Recover a service configuration while preserving valid overrides",
  "acceptance": ["Service starts", "Existing overrides survive", "Malformed input is rejected"],
  "skills": ["configuration diagnosis", "regression testing"],
  "source": {
    "benchmark_derived": false,
    "skill_paths": ["skills/service-recovery/SKILL.md@immutable-revision"],
    "scenario": "An authored service configuration incident",
    "license": "License identifier and reuse basis"
  }
}
```

For `repo`, replace the source details with `repository`, `base_commit` (40 hex
characters), `license`, and `workflow`. For `pr-issue`, use `repository`,
`base_commit`, `license`, `reference` (issue/PR URL), and `reproduction` (command,
expected failure, observed failure); optionally record `fix_commit` (40 hex).
Every source retains `benchmark_derived: false`. This declaration is reviewed in
QA; it is not itself proof of provenance. Keep detailed source receipts alongside
the candidate, outside the agent image.

Acceptance criteria must be observable behaviors, with one or more checks per
criterion. Record realistic constraints, edge cases, plausible wrong solutions,
resource requirements, and an estimated difficulty rubric before implementation.
Difficulty follows the work required; do not inflate it with obscure instructions,
unavailable services, slow downloads, or accidental environment breakage.

Candidate state progresses from authored to draft-checked to reviewed to accepted.
Only `qa_task.py` can produce the final acceptance report. Its fingerprint covers
the normalized candidate, every task file, and executable permissions. A changed
task needs new review and runtime results. Release review must verify the report
fingerprint against the actual package being published.
