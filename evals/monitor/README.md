# Evals

Behavioral evals for this setup's extensions. See [`WORKFLOW.md`](WORKFLOW.md) for the
full story of how this benchmark was built and used to optimize and simplify the
monitor extension. Currently one eval:

## monitor-bench — does a model spontaneously use the monitor extension?

The monitor extension ([`forks/pi-process-monitor-safe`](../../forks/pi-process-monitor-safe))
lets an agent watch long-running processes and get pinged on milestones/failures instead
of blocking or polling. This eval measures whether a model reaches for that on its own.

**The task prompts never mention monitors, watchers, or background tools.** Each task is an
ordinary goal whose commands happen to run a long, seeded, unknown amount of time. The
model's tool environment is a headless Pi session whose only extra package is the monitor
fork — identical across models, so the model is the only variable.

### Tasks

| task | scenario | monitor-beneficial behavior |
|------|----------|------------------------------|
| t1 | 90–180 s integration suite + a coding side-task | watch the suite, code in parallel |
| t2 | ETL pipeline that crashes mid-run on a corrupt row; fix + re-run | react to the failure ping |
| t3 | HTTP service with 45–120 s boot; verify `/status` once listening | wait for the ready line without blocking |
| t4 | Detached batch job writing `batch.log` for 90–180 s | tail the log, react to the final line |
| t5 | Control: three <5-second chores | should NOT use a monitor |
| t6 | 150–210 s export job that prints ONLY a progress bar; check on it ~every minute | heartbeats: periodic check-ins when nothing can match |
| t7 | Quiet training run, weights-write output ~every 70 s; check on it ~every minute | heartbeats: on-schedule check-ins between sparse lines |

### Metrics

- **Adoption** — `monitor` used on t1–t4 and t6–t7 (want yes), t5 (want no).
- **Trust** — `bash_blocking_seconds`: wall time in bash calls >15 s (sleep loops, inline waits).
  A model can "adopt" the tool yet still block; the interesting signal is going idle and
  letting pings drive the session (`spontaneous_wakeups`).
- **Outcome + evidence** — task goals met, checked against seeded ground truth
  (`tasks/<tN>/expected.py <seed>`, never shipped into the model's workspace). Long jobs
  must also leave **runtime artifacts** (`suite_result.json`, `output/summary.json`,
  `batch_done.json`, `render_*.done`, the live server's pid) carrying the per-run nonce
  and a plausible elapsed time — so a model cannot shortcut by recomputing results from
  fixture source (t3's build id is derived from the server's pid, not the seed).
- **Integrity** — shipped fixture files are hashed before the run; the scorer flags any
  modification outside the sanctioned edit targets (`t1: src/parse_duration.py`,
  `t2: etl/run_pipeline.py`, `t5: greet.py`), e.g. a model editing a job script to
  shorten its runtime.

The watcher accounting used for quiescence and metrics has its own self-test:
`bun harness/accounting.selftest.ts` (covers the historical false-positive where reading
the SKILL.md text was miscounted as a watcher event).

### Usage

```bash
cd evals/monitor
SEED=42 MODEL="openrouter/z-ai/glm-5.3-flash" ./run.sh   # pi (default), all tasks in parallel
HARNESS=p    SEED=42 ./run.sh                             # p lean profile (no monitor by design)
HARNESS=occ  SEED=42 ./run.sh                             # Claude Code via the occ wrapper
HARNESS=ocdx SEED=42 ./run.sh                             # Codex CLI via the ocdx wrapper
python3 score/score.py results/latest-<harness>           # one scorer for every harness

HARNESSES="pi occ ocdx" ./run-multi.sh                    # harnesses x models x seeds, fully parallel
python3 score/aggregate.py results/latest-multi           # per-model adoption/trust/blocking summary
```

The eval has **no pinned agent copy**: `pi`/`p` resolve to the installed CLIs
(version, reasoning patches, and model catalog come from the live setup) and
`occ`/`ocdx` to the installed wrappers, so updating the setup never requires
touching this eval. `meta.json`/`run.json` record the live `agentVersion` each
run measured — compare runs by that field, not by an eval-side pin. OpenRouter
credentials come from `OPENROUTER_API_KEY` or, when unset, the setup's own
`pi auth` chain.

Harness runners: `harness/run-cli.ts` drives pi/p over `--mode rpc` (one-shot
print modes exit at `agent_settled` and drop active watchers, so the bench's
wake-up semantics require a held-open session; the RPC stream is the same
AgentSessionEvent stream the old SDK harness consumed, so `accounting.ts`,
transcripts, and the scorer are unchanged, and the per-task budget is now
enforced unconditionally — the old SDK path could hang forever inside
`prompt()` when a model entered a degenerate tool loop). For `HARNESS=pi` the
isolated agent dir's only package is the monitor fork, symlinked from the
setup's INSTALLED compiled copy (`~/.pi/agent/local/pi-process-monitor-safe`,
falling back to building this repo's fork). `harness/run-external.py` drives
the one-shot occ/ocdx CLIs and normalizes their streams into the same
artifacts (`Bash`/`exec_command`/`write_stdin` -> `bash`, `apply_patch` ->
`edit`; raw output kept in `stream.jsonl`); a 25 s grace window after CLI exit
mirrors the pi quiescence settle. `harness/launch-task.sh` dispatches by
`HARNESS`. External-harness runs always score `used_monitor=False` (no such
tool there) and their t6/t7 heartbeat checks are structural failures; the
comparable signals are outcome substance, `bash_blocking_seconds`, and native
async usage visible in `toolCounts`.

Results land in `results/<timestamp>_<harness>_<model>_seed<N>/` (gitignored):
per-task workspace, full event transcript, `run.json`, and `scores.json` at the top.
Runs whose model output is empty or degenerate (rare API glitches) are flagged
`INVALID RUN` by the scorer and excluded from scores.

Reproducibility knobs: `SEED` drives all fixture runtimes deterministically; the agent
version is whatever the live setup provides and is recorded per run in `meta.json`; the
t3 service grabs an ephemeral free port at session start (bind-to-0), so concurrent runs
don't collide (a tiny TOCTOU window remains between allocation and the fixture's rebind).

Known property: duration formulas live in fixture source, so a model that reads the source
could compute runtimes. That affects timing strategy, not the need to handle a long job —
and results themselves are runtime-bound (see evidence checks above).

### Reference results (simplified extension surface: 3 tools, 6 params, 1 guideline)

Three seeds x four models, trust = monitor used AND zero sleep-blocking (of 12 long-job tasks;
one degenerate-output run excluded, hence deepseek's /11):

| model | adoption | trust | avg block (s) | outcome |
|-------|:---:|:---:|:---:|:---:|
| openai/gpt-5.6-luna | 12/12 | 9/12 | 12 | 0.95 |
| openrouter/deepseek/deepseek-v4-flash-0731 | 10/11 | 9/11 | 6 | 0.96 |
| openrouter/qwen/qwen3.8-max | 10/12 | 9/12 | 36 | 1.00 |
| openrouter/z-ai/glm-5.2 | 12/12 | 11/12 | 11 | 0.98 |

On the pre-simplification surface (4 tools, 10 params, 3 guidelines) the same benchmark
measured trust 10/8/8/6 with average blocking 27/28/33/79 s — the simplification
improved every model, glm most of all.

With the heartbeat-native tasks t6/t7 added (and `heartbeatMinutes` restored), and
after t7 was hardened so its output is invisible to default watchers: trust 14–15/18
per model with no degradation on t1–t4, heartbeats configured in 17/24
heartbeat-task runs at the requested ~1-minute cadence, and t6/t7 trusted in 21/24.
Average blocking time across the final run: 5–23 s per model.

(History: an earlier two-parallel-render-jobs task occupied the t5 slot but was removed
as contrived; the control task was renamed t6 → t5 to close the gap.)
