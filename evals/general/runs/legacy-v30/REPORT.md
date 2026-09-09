# General Eval — Full Results

Date: 2026-09-02/03 · Host: minkyukim-ThinkStation-P620 (64 cores)
Dataset: `pi-setup/evals/general` (765 tasks, commit 1855e2db)
Harness: harbor 0.22.0 (venv at `/home/ee/general-eval-runs/venv`)
Models via OpenRouter: `z-ai/glm-5.3-flash`, `deepseek/deepseek-v4-flash-0731`
Concurrency: 64 trials per run. 6 main runs + catch-up re-runs for infra failures.

## Scores (total reward / 765, catch-ups merged)

| Harness              | glm-5.3-flash | deepseek-v4-flash-0731 |
|----------------------|---------------|------------------------|
| pi (user's `p` setup) | **0.830** (635.05) | 0.811 (620.03)    |
| terminus-2           | 0.817 (625.20) | 0.758 (579.70)        |
| claude-code          | 0.820 (627.50) | **0.830** (634.90)    |

Harness notes:
- pi run = `agents/p_agent.py` PAgent: pi with the lean `p` profile
  (`--no-extensions --no-skills`), pinned pi 0.84.3 + reasoning-details patch.
- claude-code ran against OpenRouter's Anthropic-compatible endpoint
  (`https://openrouter.ai/api`), bare model slugs.

## Setup fixes made along the way

- Synced 85 gitignored fixture files (root `.gitignore` has `*.log`) from the
  `general-v3` working copy into `pi-setup/evals/general`, plus the 5 large
  assets; tree is now byte-identical to `general-v3`.
- Built `bench-base:{python-3.12,ubuntu-24.04,node-22}` images; pulled
  `texlive/texlive`.
- Installed harbor 0.22.0 (p_agent.py targets its `model_connection` API; the
  tb2 venv keeps 0.18.0).
- `p_agent.py` `_PATCH_PI_BUNDLE` pointed at the wrong file (bun script under
  `pi-setup/bin`); fixed to `bases/patch-pi-bundle` (python, same script baked
  into bench-base). This unblocked `v1-item-052-main` (texlive) for pi runs.
- Claude-code setup timeout raised 4x (64 parallel npm installs of the claude
  CLI exceed the default 360s), +2 retries on setup timeout.

## Unsorable tasks (count as 0 in all runs)

- `cinder-hearth`: image build fails — `busybox-static` apt download fails
  behind the network proxy during docker build (all 6 runs).
- `drift-canyon`: verifier bug — `tests/hidden/h3-edge/bundles/` does not
  exist in the dataset, verifier crashes before writing reward (all 6 runs).

## Catch-up re-runs (merged, higher priority than main)

- pi-glm: cobalt-quill 1, quartz-wharf 1, zephyr-summit 1, v1-item-052-main 1,
  flint-fathom 0, larch-hearth 0.
- pi-dsk: v1-item-052-main 1.
- terminus-glm: hollow-atlas 1, kite-yonder 1, onyx-ember 1; calm-canyon still
  fails (in-container tmux server dies, repros on retry — likely OOM within
  the task's 2G memory cap).
- terminus-dsk: kite-anchor 1, larch-ember 1.
- claude-code: none needed.

## Trace retention

Everything is retained in `/home/ee/general-eval-runs/`:
- `jobs/` — raw harbor job dirs (agent logs, sessions, verifier output,
  results) for all 12 runs.
- `backup/` — rsync copy.
- `archive/` — per-run `.tar.zst` (12), merged per-task records
  (`archive/final-records/<run>/<agent>/<task>/`), `METADATA.txt`.
- `failed-attempts/` — first claude-glm attempt (setup timeouts), kept for
  the record.
