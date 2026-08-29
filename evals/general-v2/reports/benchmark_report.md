# general-v2 benchmark report

Generated 2026-08-27; updated 2026-08-29 with the claude-code run and the
three-agent comparison (`reports/comparison_glm53flash.md`). Frozen clean-room
suite; model runs on `openrouter/z-ai/glm-5.3-flash`.

## Suite

- **204 Harbor tasks** (all oracle-verified from pristine containers; two full
  oracle sweeps reproduced identically).
- Difficulty: 2 easy / 84 medium / 118 hard (deliberately hard-leaning).
- Competency coverage: **722 / 726** atomic Terminal-Bench competencies have a
  real verifier-backed task; 4 are documented environmentally infeasible on this
  host (GPU Triton kernels, Linux-kernel rebuild x2, telephony interaction).
- Every task verifier executes the requested deliverables and carries 2-4 hidden
  generalization cases.

## Benchmark runs (204 trials each, 1 sample/task)

| Agent | Verifier-authoritative | Strict (agent-timeout forces 0) |
|---|---|---|
| **claude-code** | **146/204 = 0.716** | **129/204 = 0.632** |
| **terminus-2** | **141/204 = 0.691** | 107/204 = 0.525 |
| **pi (PAgent, the user's `p` setup)** | **136/204 = 0.667** | 136/204 = 0.667 |

Claude Code 2.1.251 (harbor `claude-code` agent, bypassPermissions), model via
OpenRouter's Anthropic-compatible endpoint — same serving path as the other two
runs. Its merged records audited clean (0 problems, 204/204 valid). Full
details, per-bucket splits, cost (≈$24 real pricing), and caveats:
`reports/comparison_glm53flash.md`.

- Verifier-authoritative = the harness-native rule: the verifier verdict on the
  final container state is the grade (Terminal-Bench semantics). Under this rule
  pi's agent-timeout trials never left a passing state, so pi is identical under
  both conventions.
- Strict additionally forces 0 for any trial that recorded an AgentTimeoutError
  even when the verifier passed on the post-timeout state. terminus-2 frequently
  completes the work and keeps exploring past budget, hence the divergence.
- Both conventions are published; the verifier-authoritative number is primary.

## Grading legitimacy (the audit that produced these numbers)

Every one of the 408 trials (204 x 2 agents) was forensically classified.

- **False positives: 0.** No trial scored 1 without the verifier's substantive
  checks passing.
- **True capability failures: verified.** Each TRUE_FAIL cites the concrete
  verifier check that failed on the agent's deliverable.
- **Budget failures:** agent/verifier timeouts scored as failures — working
  within budget is part of the competency.
- **Defects found and eliminated before the final numbers:**
  - 28 tasks had verifier/instruction contract defects (undocumented flags,
    unpublished output keys, unpassable byte-exact checks, verifier crashes,
    ambiguous specs). All repaired; verifiers now enforce only what the
    instruction promises and are crash-proof (always write a reward).
  - All 28 repaired tasks re-verified oracle-green and re-run for both agents;
    those fresh trials replace the original grades.
  - Verifier bugs fixed along the way: reward-file-write guarantees
    (drift-grove, umber-summit, drift-atlas, gale-ledge), port-collision
    (raven-orchid), bounded deliverable execution (amber-dial), reward-format
    (tundra-orchid), IPv6 getent ordering (tundra-bridge), PTY timing
    (dune-beacon).
  - After remediation, every trial has a clean verifier verdict; remaining
    failures are model-capability or budget, not infrastructure.

## Why these scores are lower than typical Terminal-Bench numbers

- The suite is intentionally hard: 118/204 tasks are hard and every task adds
  hidden generalization cases, so partial/hard-coded solutions fail.
- Runs used a flash-class model (glm-5.3-flash), not a frontier model.
- Difficulty floors are enforced: every competency is covered by a task at least
  as hard as its reference evidence.

## Independence (contamination)

Final audit over 30,128 payloads (incl. archive members):
`exact=0 block=0 ngram=0 canary=0 source_repository=0`. All residual
collisions are documented informational categories (language idioms, generic
vocabulary, official distribution archives, hash-pinned x264 encoder-signature
video fixtures). Two blind reviewers cleared all 6 low-similarity flagged pairs
with no direct-recipe verdicts.

## Artifacts

- `specs/` coverage, difficulty, provenance, independence, similarity reports
- `reports/blind_review_verdicts.json`
- `private-audit/` frozen reference manifest, competency map, infeasibility
  records, decisions log (D1-D3), this and prior reports
- Raw trials: `/mnt/data/general-v2-jobs/`
