# general-v2 agent comparison — glm-5.3-flash (2026-08-29)

Three agents on the same 204-task suite, same model
(`openrouter/z-ai/glm-5.3-flash`), same scoring conventions
(`private-audit/DECISIONS.md` D3/D4):

- **pi (PAgent)** — the `p` lean profile (pi, `--no-extensions --no-skills`),
  model served through OpenRouter's OpenAI-compatible API.
- **terminus-2** — OpenHands Terminus 2, model through OpenRouter.
- **claude-code** — Claude Code 2.1.251 (native build, harbor's
  `claude-code` agent, permission-mode bypassPermissions), model through
  OpenRouter's Anthropic-compatible `/v1/messages` endpoint
  (`ANTHROPIC_BASE_URL=https://openrouter.ai/api`, model slug
  `z-ai/glm-5.3-flash`). Setup follows the GLM/Claude Code integration docs;
  the OpenRouter key was used at the user's request, which also keeps the
  serving path identical to the other two runs.

## Headline scores (204 trials each)

| Agent | Verifier-authoritative | Strict (agent abort → 0) |
|---|---|---|
| claude-code | **146/204 = 0.7157** | **129/204 = 0.6324** |
| terminus-2  | 141/204 = 0.6912 | 107/204 = 0.5245 |
| pi (PAgent) | 136/204 = 0.6667 | 136/204 = 0.6667 |

claude-code leads under both conventions. terminus-2's verifier-authoritative
score is inflated relative to its strict score by 34 timeout-with-passing-state
trials (it often finishes the work and then keeps exploring past the budget);
pi has no such gap (its 6 timeouts were all unfinished work).

## Per difficulty bucket (verifier-authoritative)

| Bucket | pi | terminus-2 | claude-code |
|---|---|---|---|
| easy (2)   | 2/2 = 1.000 | 1/2 = 0.500 | 1/2 = 0.500 |
| medium (84) | 63/84 = 0.750 | 67/84 = 0.798 | 66/84 = 0.786 |
| hard (118)  | 71/118 = 0.602 | 73/118 = 0.619 | 79/118 = 0.669 |

(All three agents' bucket splits computed from the same merged records.)

category note: claude-code wins the hard bucket by 6–8 points; the easy bucket
is a 2-task sample and not meaningful.

## Audit status

- **claude-code run audited clean**: `tools/audit_run_rewards.py` over the
  merged final records — 204/204 trials valid, 0 problems (no reward.txt /
  result.json mismatch, no missing artifacts, no infra failures in the final
  set). Classes: 129 PASS, 17 TIMEOUT_PASS, 24 TIMEOUT_FAIL, 3
  TIMEOUT_NOVERDICT, 31 FAIL.
- Infra remediations during the run (all re-run to clean verdicts):
  - 30 trials failed the in-container agent install under 20-way concurrency
    (AgentSetupTimeoutError / apt or curl flakes) → re-run at lower
    concurrency.
  - basalt-bridge and hollow-notch sabotaged the installer's own facilities
    (broken /usr/bin/curl; DNS-free nsswitch) — the claude-code CLI is now
    pre-baked into those two images before the sabotage (DECISIONS D7);
    sabotages verified intact, oracles re-passed, trials re-run.
  - quartz-helix: the verifier crashed (KeyError on a malformed-but-accepted
    series output) instead of scoring 0 — verifier parse sites hardened
    (DECISIONS D6), oracle re-passed, negative control clean, trial re-run.

## Cost (real pricing, not the agents' self-reported cost)

glm-5.3-flash on OpenRouter: $0.075/1M input, $0.25/1M output. The claude-code
run consumed ≈296M input tokens (≈258M of them cached) and ≈7.5M output tokens
over 236 trials (204 + re-runs) ≈ **$24 at list pricing**. Note: the
`cost_usd` recorded in claude-code trajectories (~$5/task) is computed with
Sonnet-class pricing and must NOT be used for this agent; pi/terminus-2
trajectories report OpenRouter-accurate costs.

## Known caveats

1. The claude-code CLI (inert binary) is pre-baked into the basalt-bridge and
   hollow-notch images (D7); pi/terminus-2 records for those two tasks predate
   the binary. Task semantics and verifiers are unchanged.
2. The quartz-helix verifier was hardened (D6) after the original pi and
   terminus-2 runs; the hardening only converts verifier crashes into clean 0
   grades — neither pi nor terminus-2 ever hit those crash paths (their
   outputs parsed), so their scores are unaffected.
3. claude-code ran with `--permission-mode bypassPermissions` (harbor default
   for this agent), matching the autonomous setting of the other two agents.
4. 3 claude-code trials ended in agent timeout without a verifier verdict
   (scored 0 under both conventions, same treatment as the pi run's
   TIMEOUT_NOVERDICT trials).
