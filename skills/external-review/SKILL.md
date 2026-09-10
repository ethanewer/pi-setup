---
name: external-review
description: Run external reviews over significant pi-setup changes via the cursor-agent CLI before committing. Use when asked for an external review or audit of changes to this repo, or before committing changes to the installer, wrappers, patches, forks, skills, bin/, evals/, or tests/.
---

# External review of pi-setup changes

`cursor-agent` runs read-only reviews over changes to this repo. The reviewer
returns text and never edits files. Review significant changes before
committing, and repeat the review-and-fix cycle until the reviewers come back
clean.

## When to run

A change is significant when it touches anything the setup installs, runs, or
measures:

- install and bootstrap: `install.sh`, `install.ps1`, `lib/install.mjs`,
  `lib/versions.json`, `lib/wrappers/`, `patches/`, `vendor.json`
- shipped runtime: `forks/`, `skills/`, `extensions/`, the config writer in
  `lib/install.mjs`
- tools: `bin/`, including the `bin/convert-pi-traces` exporter
- measurement: `evals/` (harnesses, runners, scorers, harbor agents)
- `tests/`

Skip results artifacts, comment-only edits, and prose typos. When in doubt,
run the review. It takes a few minutes and catches the bugs this repo has hit
before: extensions that silently load nothing, evals pinned to stale agent
versions, budgets a hung call can bypass, shell-quoting bugs in generated
commands.

## Which reviews to run

Review 1 runs on every significant diff. Reviews 2 and 3 run only when the
diff touches `evals/`, and review 2 also covers `bin/convert-pi-traces`.
Setup, wrapper, fork, and skill changes get review 1 alone. That layer has
its own gates: `bin/pi-setup-doctor`, the installer's refusal to continue
after a partial install, and the repo tests.

Run each review as a separate invocation. In a combined prompt, findings from
one category hide behind another.

| Diff touches | Reviews |
|---|---|
| anything significant | 1 |
| `evals/` or `bin/convert-pi-traces` | 1 and 2 |
| `evals/` | 1, 2, and 3 |

## Invoking

`cursor-agent` is on PATH at `~/.local/bin/cursor-agent`. Use the full path if
PATH misses. Set the workspace to the git root of the checkout under review.
Reviews run for minutes, so launch each under the background watcher/monitor
tool when the session has one, and keep working instead of polling.

New files are invisible to `git diff` until staged. Make them visible without
committing:

```bash
git add -N <each new file>
```

Invocation shape. The text output is the report.

```bash
~/.local/bin/cursor-agent -p -f --trust --workspace <repo root> "<prompt>"
```

`-p` is print mode. `-f` pre-approves the reviewer's read-only shell and git
calls. `--trust` skips the workspace prompt.

### Review 1: software quality (bugbot)

```text
Use the review-bugbot skill. Launch one bugbot subagent (run_in_background=false).
Full Repository Path: <repo root>
Diff: uncommitted changes
The subagent computes the diff itself. Do not precompute it. Report findings as a
Severity | file:line | Finding table, sorted by severity (high first). Do not fix anything.
```

Use `Diff: branch changes` when the work is already committed on a branch.
Expect "nothing to review" on an empty diff, one line when clean, and the
severity table otherwise.

### Review 2: measurement correctness (eval changes only)

A scoring bug that silently invalidates a benchmark is worse than a code bug,
and bugbot cannot see it. This is a plain cursor-agent review.

```text
Read-only external review of the uncommitted changes in <repo root> (git diff HEAD,
including intent-to-add files). Check measurement and scoring correctness, not style.
1. For each changed measurement path, state what it claims to measure: adoption,
   blocking seconds, watcher accounting, outcome checks, token accounting, dataset
   lane routing.
2. Verify normalization preserves what the scorers compute: tool-name mappings,
   call and result pairing by id, timestamp-based durations, error and exit-code
   mapping.
3. Re-derive the arithmetic: token sums, blocking sums, ratios, caps, dedupe keys.
4. Check concurrency and lifecycle: parallel-task races on shared state, budget
   enforcement a hung call cannot bypass, process-group cleanup, LF-only JSONL
   framing.
5. Run the cheap checks yourself: bun test on the touched test files, selftests,
   python syntax checks. Use /tmp for scratch. Never edit project files.
Return text only: a one-paragraph verdict, a Severity | file:line | Finding table
with high findings first, and the checks you ran with results. Do not fix anything.
```

### Review 3: live-setup contract (eval changes only)

The evals must measure the operator's current setup and must never drift from
it silently. This review checks that contract whenever eval code changes.

```text
Read-only external review of the uncommitted changes in <repo root> (git diff HEAD,
including intent-to-add files), focused on the eval-to-setup contract. Not style.
1. No agent-version pins outside lib/versions.json. Evals must resolve pi, p, occ,
   ocdx, and the harbor-side claude and codex engines from the live setup at run
   time. Flag any hardcoded version, stale catalog snapshot, or copied patch or
   wrapper that can drift.
2. Derivation fails loud. When a setup value (pin, patch file, wrapper, compiled
   fork, managed config, credential) cannot be resolved, the eval must refuse to
   run rather than fall back to @latest, a neighboring version, or a degraded
   tool set.
3. No silent degradation. Extension loading, bake checks, and materialize steps
   must verify their result. The historical failure here was a missing compiled
   entry that made pi load zero extensions without an error.
4. Wrapper fidelity. Evals that drive occ or ocdx must go through the setup
   wrappers, which own the endpoint pin, the closed-model refusal, and the
   isolated state dirs, rather than re-deriving that environment.
5. Shared-state safety. Directories shared by parallel tasks use create-once or
   atomic rename-aside semantics, never in-place removal while another task may
   be loading.
Run cheap verification where possible: bash -n, syntax checks, grep for pins.
Use /tmp for scratch. Never edit project files.
Return text only: a verdict paragraph, a Severity | file:line | Finding table with
high findings first, and the checks you ran with results. Do not fix anything.
```

## Treating results

Findings are advice, not truth. Verify each one against the code before
acting. Agree with evidence, or refute it. A finding you cannot confirm is
not a fix. Fix the confirmed issues, re-run the same reviews, and loop until
bugbot reports no findings and the other reviews leave no unaddressed high or
medium finding. Commit only after a clean round. The reviewer never edits
files. The working agent makes the fixes and runs the repo's tests afterward.
