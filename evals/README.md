# Evals

Behavioral evals for this setup's extensions. See [`WORKFLOW.md`](WORKFLOW.md) for the
full story of how this benchmark was built and used to optimize and simplify the
monitor extension. Currently one eval:

## monitor-bench — does a model spontaneously use the monitor extension?

The monitor extension ([`forks/pi-process-monitor-safe`](../forks/pi-process-monitor-safe))
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
| t7 | Quiet training run, checkpoint output ~every 70 s; check on it ~every minute | heartbeats: on-schedule check-ins between sparse lines |

### Metrics

- **Adoption** — `monitor` used on t1–t4 (want yes), t5 (want no).
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
cd evals
SEED=42 MODEL="openai/gpt-5.6-sol" ./run.sh          # one model, all tasks in parallel
python3 score/score.py results/latest

./run-multi.sh                                        # 4 models x 3 seeds x all tasks, fully parallel
python3 score/aggregate.py results/latest-multi       # per-model adoption/trust/blocking summary
```

`run.sh` installs dependencies on first use (Bun; pins `@earendil-works/pi-coding-agent`,
see `package.json`). Results land in `results/<timestamp>_<model>_seed<N>/` (gitignored):
per-task workspace, full event transcript, `run.json`, and `scores.json` at the top.
Runs whose model output is empty or degenerate (rare API glitches) are flagged
`INVALID RUN` by the scorer and excluded from scores.

Reproducibility knobs: `SEED` drives all fixture runtimes deterministically; the harness
links the monitor fork from `forks/` (falls back to `~/.pi/agent/local/`); the Pi package
version is pinned in `package.json`; the t3 service grabs an ephemeral free port at
session start (bind-to-0), so concurrent runs don't collide (a tiny TOCTOU window
remains between allocation and the fixture's rebind).

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

(History: an earlier two-parallel-render-jobs task occupied the t5 slot but was removed
as contrived; the control task was renamed t6 → t5 to close the gap.)
