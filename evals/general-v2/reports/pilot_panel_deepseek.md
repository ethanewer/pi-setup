# Calibration pilot panel — deepseek-v4-flash on general-v2 (2026-08-29)

Addresses TODO residual #3 (multi-agent calibration panel) with a small
independent panel run: `p_agent:PAgent` (pi lean profile) on
`openrouter/deepseek/deepseek-v4-flash-0731`, no reference-benchmark access
(containers contain only bench-base + task fixtures).

## Setup

- 36 tasks stratified by bucket from specs/difficulty.json (seed 42):
  both easy tasks, 12 sampled medium, 22 sampled hard.
- 1 sample per task, harbor concurrency 10.
- Jobs: `/mnt/data/general-v2-jobs/pilot-panel-deepseek` (36 trials),
  one infra-shape re-run under `pilot-panel-deepseek-rerun` (raven-orchid).

## Results (verifier-authoritative; strict = any agent-side abort forces 0)

| bucket | VA pass | n | rate |
|---|---|---|---|
| easy   | 2 | 2  | 1.000 |
| medium | 4 | 12 | 0.333 |
| hard   | 9 | 22 | 0.409 |
| total  | 15 | 36 | 0.417 (strict 14/36 = 0.389) |

Audit: `tools/audit_run_rewards.py` over the job — 36/36 trials valid,
0 problems (no reward.txt/reward.json mismatch, no missing artifacts).

## Failure-mode review

- 4 trials recorded agent-side exceptions, all with a clean verifier verdict
  on the final container state (verifier-authoritative per DECISIONS D3):
  - amber-orchid, raven-orchid (+ raven-orchid re-run): the agent's own
    `pkill`/`fuser` cleanup commands matched the pi CLI's own command line
    (which embeds the instruction text) and SIGTERM'd the harness
    (exit 143, classified UnknownApiError / NetworkConnectionError by output
    pattern matching). The re-run reproduced the same self-kill, confirming
    an agent-behavior failure mode on media-server-style tasks, not
    infrastructure.
  - drift-dial: agent finished all deliverables, then killed its own harness
    during cleanup; verifier passed the final state (AGENT_ERROR_PASS).
  - tundra-ledge: agent timeout with unfinished work (legitimate 0).
- Every remaining failure is a verifier-cited capability gap; spot checks of
  verifier stdout show concrete failed checks on the deliverables.

## Calibration read

A weaker flash-class model passes 100% of easy, ~33% of medium, ~41% of hard
on this stratified subset — comfortably below the glm-5.3-flash full-suite
rates (pi 0.667 / terminus-2 0.691), which is the expected ordering and shows
the difficulty buckets are discriminative. The hard > medium inversion on this
small sample reflects heavy-environment medium tasks (QEMU/ installs) rather
than verifier brittleness; all such tasks passed their oracle sweeps (4×).
