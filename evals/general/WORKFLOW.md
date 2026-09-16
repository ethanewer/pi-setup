# General evaluation task workflow

New tasks enter through exactly three authoring pipelines. All produce the same
candidate contract and task package, and all pass the same [QA backend](qa/README.md).
Existing tasks and their recorded results remain valid historical artifacts.

| Front end | Starting material | Authoring guide |
| --- | --- | --- |
| Skills to task | Real skill instructions and practical workflows | [Skills](authoring/skills.md) |
| Repo to task | A pinned production repository and a useful engineering objective | [Repository](authoring/repo.md) |
| PR/issue to task | A real issue or change with a reproducible before/after behavior | [PR/issue](authoring/pr-issue.md) |

Benchmarks must never supply scenarios, objectives, coverage targets, solutions,
tests, repository selections, or difficulty targets for any authoring pipeline.
Select work by practical value, skill gaps in this suite, domain diversity,
reproducibility, and the strength of its observable success criteria.

## Authoring and handoff

For multi-source runs, start with the [bounded batch queue](authoring/BATCHES.md).
It supplies all three fronts with the same generation settings, resumable claims,
repair accounting, isolated drafts and QA handoff. Use the steps below for the
candidate and release contract; batch generation never bypasses acceptance gates.

1. Select a source using one of the three guides. Record its identity, immutable
   revision, license, and the exact material consulted. Deduplicate against the
   suite by repository/revision/issue and by objective, not just task name.
2. Write a candidate using the [common contract](authoring/README.md). Normalize
   it with `python3 tools/author_task.py skills --input source.json --output authoring/candidates/my-task.json`
   (use `repo` or `pr-issue` for the other front ends). Output is exclusive: a
   repeated command cannot overwrite a previous candidate.
3. Author `tasks/<task_id>/`: `instruction.md`, `task.toml`, `difficulty.json`,
   `environment/Dockerfile`, `solution/solve.sh`, `tests/test.sh`, and hidden cases.
   Use the schema and resource conventions of existing tasks. Instructions must
   state all required deliverables and behavior without leaking the solution.
4. Submit the candidate and package to QA. A draft check is useful during authoring:
   `python3 tools/qa_task.py --candidate authoring/candidates/my-task.json --static-only`.
   A draft result is never permission to publish.
5. Complete independent review and runtime controls using the QA guide. Repair
   failures and resubmit; edits invalidate the prior review fingerprint.
6. Register accepted tasks additively, preserve existing difficulty labels and
   task contents, and include the acceptance report in the release review.
   Use `python3 tools/register_task_wave.py --names my-task --wave my-wave --dry-run`,
   then omit `--dry-run` to write. Registration requires the matching candidate
   under `authoring/candidates/` and an accepted report for its current fingerprint.

Do not regenerate existing tasks or use older wave slot generators to author new
ones. Historical specs, run records, and task metadata describe prior releases;
they are not input requirements for the new pipelines.
