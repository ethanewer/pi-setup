# Evals

Behavioral evals for this setup's extensions. Currently one eval:

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
| t5 | Two independent render jobs (60–140 s, 90–200 s) | track both, clean up |
| t6 | Control: three <5-second chores | should NOT use a monitor |

### Metrics

- **Adoption** — `monitor` used on t1–t5 (want yes), t6 (want no).
- **Trust** — `bash_blocking_seconds`: wall time in bash calls >15 s (sleep loops, inline waits).
  A model can "adopt" the tool yet still block; the interesting signal is going idle and
  letting pings drive the session (`spontaneous_wakeups`).
- **Outcome** — task goals actually met, checked against seeded ground truth
  (`tasks/<tN>/expected.py <seed>`, never shipped into the model's workspace).

### Usage

```bash
cd evals
SEED=42 MODEL="openai/gpt-5.6-sol" ./run.sh          # all 6 tasks in parallel
python3 score/score.py results/latest
```

`run.sh` installs dependencies on first use (Bun; pins `@earendil-works/pi-coding-agent`,
see `package.json`). Results land in `results/<timestamp>_<model>_seed<N>/` (gitignored):
per-task workspace, full event transcript, `run.json`, and `scores.json` at the top.

Reproducibility knobs: `SEED` drives all fixture runtimes deterministically; the harness
links the monitor fork from `forks/` (falls back to `~/.pi/agent/local/`); the Pi package
version is pinned in `package.json`.

Known property: duration formulas live in fixture source, so a model that reads the source
could compute runtimes. That affects timing strategy, not the need to handle a long job.

### Reference results (seed 42, one trial per model)

| task | gpt-5.6-sol (monitor · wakeups · block s) | deepseek-v4-flash-0731 (monitor · wakeups · block s) |
|------|------|------|
| t1 | yes · 1 · 0 | no · 0 · 112 |
| t2 | no · 0 · 162 | no · 0 · 103 |
| t3 | yes · 2 · 0 | yes (decorative) · 0 · 105 |
| t4 | yes · 3 · 0 | yes · 0 · 150 |
| t5 | yes · 2 · 0 | yes · 2 · 0 |
| t6 | correctly none | correctly none |

Both models completed every goal; the gap is in trust — gpt-5.6-sol idled and waited for
pings (4/5 tasks), while deepseek set watchers then slept in bash anyway (1/5).
