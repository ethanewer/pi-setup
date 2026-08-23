# Workflow: from benchmark design to a simplified, better-used monitor extension

This document records the full arc of work on the `monitor-optim` branch: designing a
benchmark that measures whether models *spontaneously* use the monitor extension,
using it to diagnose weak-model behavior, iterating the extension against the
benchmark, and simplifying the extension's model surface — with measurement at every
step.

## The question

The monitor extension lets an agent start a non-blocking watcher over a long job and
get pinged on milestones/failures instead of blocking or polling. It worked well with
strong models; the open question was whether weaker models would (a) reach for the
tool unprompted and (b) actually *trust* it — go idle and let pings drive the
session — rather than start a watcher and then `sleep 60` in bash anyway.

## Phase 1 — Benchmark design

Design principles, in priority order:

1. **Never mention the tool.** Task prompts describe ordinary goals ("run the suite
   and report its result; also finish this validation change") whose commands happen
   to run a long, unknown amount of time. The word "monitor"/"watcher"/"background"
   appears in no prompt.
2. **Seeded, variable runtimes.** Every fixture derives its duration from a `SEED`
   env var (45–200 s bands), so runs are replayable but a model can't just "sleep
   the right amount".
3. **A control task.** One task with only sub-5-second chores, where using a monitor
   is a false positive.
4. **Auditable transcripts.** Every run records a full event log, session entries,
   and a per-task `run.json`, so any score can be traced back to raw behavior.

Final task set (after one removal, see Phase 4):

| task | scenario | monitor-beneficial behavior |
|------|----------|------------------------------|
| t1 | 90–180 s integration suite + parallel coding fix | watch suite, code meanwhile |
| t2 | pipeline crashes mid-run on a corrupt row; fix + re-run | react to the failure ping |
| t3 | HTTP service with 45–120 s boot; verify `/status` | wait for the ready line |
| t4 | detached batch job appending to `batch.log` | tail the log, report at the end |
| t5 | control: three fast chores | should NOT use a monitor |

Key metrics:

- **Adoption** — `monitor` used on t1–t4.
- **Trust** — monitor used *and* zero bash calls >15 s (no sleep-loops while a
  watcher runs). This became the headline metric: adoption without trust is
  decorative monitoring.
- **Outcome** — task goals met, checked against seeded ground truth.
- **Integrity** — fixture files hashed pre-run; unexpected modifications flagged.

## Phase 2 — Harness construction

Headless runs via the Pi SDK (`createAgentSession`) with an isolated agent dir
(`harness/pihome`) whose only package is the monitor fork — the model's tool/skill
environment is identical across models, so the model is the only variable. The
harness:

- copies fixtures into a fresh workspace, records fixture hashes, sets `SEED`,
  a per-run nonce, and an ephemeral free port for t3;
- subscribes to all session events → `transcript.jsonl` + `events.jsonl`;
- tracks active watchers from the event stream (needed for quiescence: a run ends
  when no watchers remain active and the session is idle, or at the wall-time budget);
- kills leftover fixture processes via pidfiles on exit.

Orchestration: `run.sh` (one model, all tasks parallel), `run-many.sh` (seed loop),
`run-multi.sh` (models × seeds × tasks, fully parallel), `score/score.py` (per-run
scoring), `score/aggregate.py` (cross-seed adoption/trust/blocking tables).

## Phase 3 — First runs and harness bugs (found by the benchmark)

The first deepseek and gpt-5.6 runs worked, but debugging the transcripts exposed
several harness and fixture bugs — each fixed before trusting results:

- **Ground-truth leak**: `expected.py` originally shipped inside the model's
  workspace; a model read it and precomputed answers. Moved outside; later all
  ground truth became runtime-bound (artifacts carrying the per-run nonce and
  plausible elapsed times; t3's build id derived from the live server's pid).
- **Ping-detection false positive**: the watcher accounting matched `[watcher …]`
  text *inside the SKILL.md content read back as a tool result*, marking watchers
  stopped and settling runs early — invalidating a whole gpt run. Fixed with a
  line-anchored, role-aware matcher and codified in `accounting.selftest.ts`.
- **Empty/degenerate turns**: rare API responses (blank or chat-template junk) look
  like failed tasks; the harness retries once, and the scorer flags such runs
  `INVALID RUN` and excludes them.
- **Port collisions**: hash-derived ports collide across large parallel batches;
  replaced with ephemeral bind-to-0 allocation.
- **A real fixture bug**: t4's batch job crashed on launch (`list - set` TypeError).
  Both models' watchers caught the crash, diagnosed it, fixed the fixture, and
  re-submitted — an accidental but perfect demonstration of failure reaction.

## Phase 4 — Baseline findings and task-set pruning

First four-model baseline (3 seeds each): adoption was already high — every model
reached for `monitor` on 3–4/4 long-job tasks — but **trust** separated them:
qwen 8/12, glm 3/12, luna 0/12, deepseek 0/12. The failure signature was universal:
start a watcher, then issue `sleep 60`-style waits in the same turn.

The original t5 (two parallel render jobs) was removed: realistic in structure but
contrived in dressing. The control task was renamed t6 → t5 to close the numbering
gap, and the scorer gained a fixture-marker guard so pre-rename workspaces are
skipped instead of mis-scored.

## Phase 5 — Optimization loop (max 3 iterations)

**iter1 — the big lever.** Diagnosis: the always-in-context guideline already said
"never block the session waiting" and was ignored; the moment of risk is right after
the `monitor` call returns. Fix: the *tool result* ("Watcher X running…") now ends
with "End your turn now; the ping will wake you. Do not sleep, poll, or re-check the
job." — delivered exactly at the decision point, only when a watcher starts. The same
rule was added to SKILL.md for skill readers. Trust jumped: luna 0→9, deepseek 0→7,
glm 3→9, qwen held 8.

**iter2 — silent-watcher bug.** Root-caused remaining outcome failures: relative
`logFile` paths were never resolved against the session cwd (spawn/poll already used
`ctx.cwd`), so a watcher could silently tail the wrong file forever. Fixed in
`runtime.launch()`; harness now `chdir`s to the workspace like Pi's TUI. Best overall
trust numbers.

**iter3 — residual patterns.** Two skill bullets ("fix-and-rerun loops", "work while
waiting") for the last failure shapes. Helped luna's t1 adoption; glm dipped in that
run — kept anyway as net positive, ~40 words, in the skill (read-time context) as
preferred.

Notable from transcripts: deepseek never reads the skill (0/15 tasks) — its gains
came entirely from result text and guidelines; skill-only text cannot reach it.

## Phase 6 — Simplification (usage-data-driven)

Concern: too much model surface for weak models (4 tools, 10 params, 3 guidelines).
Ground rules: no backend changes; prefer text in the skill over always-in-context
text; every cut validated by a benchmark run.

Changes applied (A* B C D F):

- **4 → 3 tools**: `monitor_kill_all` merged into `monitor_kill` — `id: "*"` is the
  intentional stop-all (chosen over optional-id to make kill-all deliberate).
- **10 → 6 params**: dropped tuning knobs (`coalesceSeconds`, `maxLines`,
  `heartbeatMinutes`, `timeoutSeconds`) no benchmark model ever set; defaults apply,
  slash flags remain.
- **3 → 1 guideline**; `monitor` description ~90 → ~60 words; skill frontmatter
  ~55 → ~25 words; SKILL.md lifecycle updated for `id: "*"`.

Result: trust 32/48 → 38/48, avg blocking down for 3/4 models (glm 79→11 s),
adoption held, kill-all used intentionally 4 times vs 27 targeted kills — no
accidental wipes. Options declined on evidence: merging `monitor_status` into
`monitor` (transcripts showed 40 genuine status calls) and aggressive skill-body
trimming (the skill repeatedly served as a repair resource weaker models consult).

A later usage sweep confirmed the surface is at its limit: `label` set in 157/159
watcher starts, `notifyOn` 150/159, `cwd` 56 — every remaining element earns its
context cost. Only micro-trim left: dropping the SIGTERM/SIGKILL mechanics sentence
from the kill tool description.

## Phase 7 — A/B validation (initial vs final)

To rule out run-to-run noise, the full benchmark was re-run with the **initial
extension** (fork at the branch base, pre-optimization) and the **final extension**,
same harness/scorer, same models × seeds, sequentially under identical load:

| model | initial trust | final trust | initial avg-block | final avg-block |
|-------|:---:|:---:|:---:|:---:|
| gpt-5.6-luna | 3/12 | 9/12 | 135 s | 8 s |
| deepseek-v4-flash-0731 | 0/12 | 10/12 | 116 s | 10 s |
| qwen3.8-max | 10/12 | 12/12 | 18 s | 0 s |
| glm-5.2 | 0/12 | 5/12 | 132 s | 134 s |
| **total** | **13/48** | **36/48** | | |

Trust nearly tripled while the surface shrank. Adoption barely moved (43→45/48):
the entire gain came from models *trusting* the tool, not reaching for it more. qwen
scored a perfect 12/12 with zero blocking seconds. glm remains the wildcard — its
`sleep` reflex produces ±5/12 swings between runs, the one behavior text hasn't
reliably fixed.

## Phase 8 — Review hardening

An external review (every finding validated before acting) caught incomplete
follow-through of the simplification, all fixed:

- `execute()` still read the four removed schema params → `npm run typecheck` red
  (4× TS2339); stale reads removed.
- `tests/smoke.sh` used `monitor_kill_all` as the "extension loaded" canary → now
  probes `monitor_kill`.
- shipped `prompts/watch.md` still advised calling the deleted tool at the watcher
  cap → now `monitor_kill` with `id: "*"`.
- README upstream-comparison table and `docs/LONG_RUNS.md` advertised the deleted
  tool → corrected.
- Added a unit test for relative-`logFile` cwd resolution with a negative control
  (test fails when the fix is reverted); corrected the evals README's port claim.

## Lessons

1. **Placement beats volume.** One sentence in the conditional tool result outdid an
   always-in-context guideline models had been ignoring. Intervene at the moment of
   the decision, not generally.
2. **Adoption ≠ trust.** Measure both; the gap between them is where weak models live.
3. **Check usage before cutting.** Data killed several plausible simplifications
   (`monitor_status`, `label`) that intuition wanted to remove.
4. **Benchmarks find real bugs.** The eval exposed two genuine extension bugs
   (relative `logFile` resolution, ping-matching false positive) plus a fixture bug —
   and one accidental crash became the best failure-reaction test we ever ran.
5. **Guard the ground truth.** Anything computable from the workspace will be
   computed by a sufficiently motivated model; bind answers to runtime state.
6. **Single trials lie.** ±2–5/12 swings per model-task are normal; compare
   distributions over seeds, and re-validate with fresh runs (the A/B) before
   believing an optimization.
7. **Verify negative controls.** The resolution test was proven to bite by reverting
   the fix; scorers were proven to catch degenerate runs by feeding them one.

## Reproducing

```bash
cd evals/monitor
./run-multi.sh                                   # 4 models x 3 seeds, all parallel
for d in results/latest-multi/*/; do python3 score/score.py "$d"; done
python3 score/aggregate.py results/latest-multi
```

Branch state: `monitor-optim` (worktree `~/pi-setup-monitor-optim`), commits cover
the eval infrastructure, the three optimization iterations, the simplification, the
merge of main, and review hardening. A/B baseline worktree: `~/pi-setup-monitor-initial`.
