---
name: external-review
description: Run external reviews over significant pi-setup changes via the cursor-agent CLI before committing. Use when asked for an external review or audit of changes to this repo, or before committing significant changes — bugbot for any significant diff, plus the measurement and live-setup-contract reviews when the eval pipeline changes.
---

# External review of pi-setup changes

The `cursor-agent` CLI runs read-only external reviews over this repository's
changes. The reviewer returns text only and never edits files; its findings are
advisory input, not truth. Significant changes are reviewed before they are
committed, and the review/fix cycle repeats until clean.

## When to run

A change is significant when it touches anything the setup installs, runs, or
measures:

- bootstrap/install: `install.sh`, `install.ps1`, `lib/install.mjs`,
  `lib/versions.json`, `lib/wrappers/*`, `patches/*`, `vendor.json`
- shipped runtime surface: `forks/*`, `skills/*`, `extensions/*`, the config
  writer in `lib/install.mjs`
- tooling: `bin/*` (including `bin/convert-pi-traces`, the dataset exporter)
- measurement: `evals/**` (harnesses, runners, scorers, harbor agents)
- `tests/**`

Skip only for results artifacts, comment-only edits, and prose typos. When in
doubt, run the review: it costs a few minutes of wall time and catches the
class of bug this repo has been burned by before (silent extension-load
failures, unpinned version drift, unenforced budgets, shell-quoting bugs in
generated commands).

## Which reviews to run

Review 1 runs for every significant diff. Reviews 2 and 3 run ONLY when the
diff touches the eval pipeline (`evals/**`; review 2 also covers
`bin/convert-pi-traces`). Setup, harness, wrapper, fork, or skill changes get
review 1 alone — that layer already has its own gates (`bin/pi-setup-doctor`,
the installer's refuse-on-partial-install behavior, and the repo's tests).

Run each applicable review as a SEPARATE invocation — never fold two review
types into one prompt; a finding from one category hides behind the other.

| The diff touches | Reviews |
|---|---|
| anything significant (setup, wrappers, installer, forks, skills, bin/, tests) | 1. software quality (bugbot) |
| `evals/**` or `bin/convert-pi-traces` | 1 + 2. measurement correctness |
| `evals/**` | 1 + 2 + 3. live-setup contract |

## Invoking

`cursor-agent` is on PATH at `~/.local/bin/cursor-agent` (use the full path if
PATH misses). The workspace is the git root of the pi-setup checkout being
reviewed. Reviews often run minutes: launch each under the background
watcher/monitor tool if the session has one and keep working; do not poll.

Before invoking, make new files visible to the diff without committing them:

```bash
git add -N <each new file>
```

Invocation shape (text output is the report):

```bash
~/.local/bin/cursor-agent -p -f --trust --workspace <repo root> "<prompt>"
```

`-p` print mode, `-f` pre-approves the reviewer's read-only shell/git calls,
`--trust` skips the workspace prompt.

### Review 1: software quality (bugbot)

```text
Use the review-bugbot skill. Launch one bugbot subagent (run_in_background=false).
Full Repository Path: <repo root>
Diff: uncommitted changes
The subagent computes the diff itself — do not precompute it. Report findings as a
Severity | file:line | Finding table, sorted by severity (high first). Do not fix anything.
```

Use `Diff: branch changes` instead when the work is already committed on a branch.
Expected results: "nothing to review" on an empty diff, one line when clean,
otherwise the severity table.

### Review 2: measurement correctness (eval changes only)

For eval harnesses, scorers, and the trace exporter — the analog of a
scientific-correctness review: a scoring bug that silently invalidates a
benchmark is worse than a code bug and invisible to bugbot. Prompt (plain
cursor-agent review, not bugbot):

```text
Read-only external review of the uncommitted changes in <repo root> (git diff HEAD,
including intent-to-add files). You are checking measurement and scoring correctness,
not style.
1. For each changed measurement path, state what it claims to measure (adoption,
   blocking seconds, watcher accounting, outcome checks, token accounting, dataset
   lane routing).
2. Verify normalization preserves what the scorers compute: tool-name mappings,
   call/result pairing by id, timestamp-based durations, error/exit-code mapping.
3. Re-derive the arithmetic: token sums, blocking sums, ratios, caps, dedupe keys.
4. Check concurrency and lifecycle: parallel-task races on shared state, budget
   enforcement that cannot be bypassed by a hung call, process-group cleanup,
   stream framing (LF-only JSONL; no readline).
5. Run the cheap checks yourself (bun test on the touched test files, selftests,
   python import/syntax checks). Use /tmp for scratch. Never edit project files.
Return as text only: a one-paragraph verdict; a Severity | file:line | Finding table
(high first); the checks you ran with results. Do not fix anything.
```

### Review 3: live-setup contract (eval changes only)

The evals must measure the operator's CURRENT setup and must never drift from
it silently. This review checks that contract whenever eval code changes.

```text
Read-only external review of the uncommitted changes in <repo root> (git diff HEAD,
including intent-to-add files), focused on the eval-to-setup contract. Not style.
1. No agent-version pins outside lib/versions.json: evals must resolve pi/p/occ/ocdx
   (and harbor-side claude/codex engines) from the live setup at run time; flag any
   hardcoded version, stale catalog snapshot, or copied patch/wrapper that can drift.
2. Derivation is fail-loud: when a setup value (pin, patch file, wrapper, compiled
   fork, managed config, credential) cannot be resolved, the eval must refuse to run
   rather than fall back to @latest, a neighbor version, or a degraded surface.
3. No silent degradation: extension/package loading, bake checks, and materialize
   steps must verify their result (a missing compiled entry that loads zero
   extensions is the historical failure this repo hit).
4. Wrapper fidelity: evals that drive occ/ocdx must go through the setup wrappers
   (endpoint pin, closed-model refusal, isolated state dirs) rather than
   re-deriving their environment.
5. Shared-state safety: per-arm/per-run directories shared by parallel tasks use
   create-once or atomic rename-aside semantics, never in-place removal under a
   possible concurrent loader.
Run cheap verification where possible (bash -n, syntax checks, grep for pins).
Use /tmp for scratch. Never edit project files.
Return as text only: verdict paragraph; Severity | file:line | Finding table (high
first); checks run with results. Do not fix anything.
```

## Treating results

Advisory, not truth. Verify every finding against the code before acting:
agree with evidence, or refute it. A finding you cannot confirm is not a fix,
and findings are never forwarded into edits unverified. Fix the confirmed
issues, re-run the same reviews, and loop until clean — bugbot reports no
findings, and the other reviews leave no unaddressed high or medium finding.
Commit only after the loop is clean. The reviewer does not edit files and
neither does this skill: all fixes are made by the working agent, in the
normal way, with the repo's own tests run afterward.
