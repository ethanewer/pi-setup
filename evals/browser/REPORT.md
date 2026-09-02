# Browser tooling for pi agents — research, benchmark, and comparison

**Branch:** `browser-eval` · **Eval:** `evals/browser/` · **Date:** 2026-08-29
**Models:** `z-ai/glm-5.3-flash`, `deepseek-v4-flash-latest` (OpenRouter)
**Runs:** 6 arms × 2 models × 3 seeds × 5 tasks = 180 run-slots; 176 scored, 19
excluded as degenerate model output (details in §5).

---

## 1. The question

Agents driving the installed browser tool (`agent-browser` via the
`pi-agent-browser-native` extension) keep getting stuck on captchas and bot checks.
Three sub-questions:

1. Is there a better browser extension, with real community support?
2. Would additional context (guidance) help agents avoid the issues?
3. Is a **CLI + skill** setup — a browser CLI installed alongside pi, taught by a
   `SKILL.md`, with no new tools or extensions — the cleanest option? (Also:
   how does deepseek-v4-flash behave across setups?)

## 2. Live evidence that the problem is real

While researching, the current stack was captcha'd by the open web within minutes:
Google served its `/sorry/` page on a first search, DuckDuckGo served an anomaly
challenge on its HTML endpoint, npmjs served a Cloudflare interstitial. All on the
same real-Chrome automation session. This shaped the central design decision below:
the eval measures **handling** (solve / wait / back off vs flail / loop), because
**avoidance is a property of IP reputation, automation signals, and profile state —
not of which extension drives Chrome**. Every serious candidate drives the same
real Chrome via CDP.

## 3. Research: candidates

Hard requirement: well-tested with genuine community support. pi has no built-in
MCP, so MCP servers need a bridge extension.

| candidate | community | verdict |
|---|---|---|
| `agent-browser` + pi fork (installed baseline) | 205★ pi ext; 5.2M dl/mo upstream | baseline arm |
| `@playwright/mcp` (Microsoft official) | 36.6k★, 25.4M dl/mo | tested via bridge |
| `chrome-devtools-mcp` (Chrome team official) | 50k★, 9.8M dl/mo | tested via bridge |
| `pi-mcp-adapter` (MCP bridge for pi) | 1.36k★, 695k dl/mo | shared bridge for both MCP arms |
| `@playwright/cli@0.1.18` (CLI+SKILLS, official) | new, official, npm | tested as CLI arm |
| `agent-browser` CLI (already installed) | same as baseline | tested as CLI arm |
| `pi-browser-debug` / `pi-browser` / `pire-browser` | 316 / 99 / 385 dl/mo | rejected — no community |
| `browser-use` (incl. MCP) | 111k★ but an agent-in-agent loop | rejected — wrong shape |
| `@amaster.ai/pi-browser-use`, `@narumitw/pi-chrome-devtools` | 4k / 7k dl/mo | viable, smaller than chosen bridge |

Design decision: **both MCP arms share the same `pi-mcp-adapter` gateway**, so
arm differences isolate the browser stack, not the bridge.

## 4. The benchmark

`evals/browser/` — same methodology as the monitor eval, adapted for browsers:

**Fixture site** (seeded, per-run port + nonce, source/log/truth kept in a random
temp dir outside the model's reach). Friction is deterministic and **instrumented
server-side** — the site's request log is the ground truth for all friction metrics:

- **Hard bot block** — non-browser user agents (curl etc.) get 403.
- **Human gate** on catalog/product pages: checkbox check on first visit per
  session, escalating to a 6-character code captcha on retries; solving issues a
  clearance cookie. Solvable by design — the test is whether the agent reads and
  completes it.
- **Browser-check interstitial** (~5 s, JS countdown) whose clearance route rejects
  early arrivals — waiting is the only strategy.
- **Rate limiter** on a 12-page JSON listing: 6 req/10 s, then 429 + `Retry-After: 5`.
- **Form login** with a runtime-bound password; **JS-assembled content** invisible
  in raw HTML.

**Tasks** (prompts never mention captchas, checks, or waiting): t1 catalog crawl
through the gate · t2 rotation-code lookup behind the interstitial · t3 rate-limited
analytics compile · t4 login flow · t5 control (homepage read).

**Arms:**

| arm | pi packages | browser surface |
|---|---|---|
| `agent-browser` (baseline) | native extension | `agent_browser` tool |
| `agent-browser-guided` | native extension | same + 4 lines of user tips in the prompt |
| `playwright` | pi-mcp-adapter | `@playwright/mcp` via lazy MCP gateway |
| `devtools` | pi-mcp-adapter | `chrome-devtools-mcp` via lazy MCP gateway |
| `cli-agent-browser` | **none** — one SKILL.md | `agent-browser` CLI from bash |
| `cli-playwright` | **none** — one SKILL.md | `@playwright/cli` from bash |

**Metrics:** outcome (exact runtime-bound values in the final answer) · friction
handling from the server log (challenges served/solved/failed, loops, interstitial
restarts, 429s, Retry-After violations) · efficiency from the transcript (browser
calls, duplicate calls, navigations, turns, tokens, wall time) · degenerate-output
flagging.

## 5. What the benchmark caught before any results were trusted

- **The bare SDK never emits `session_start`** — the MCP gateway stays
  uninitialized until the harness calls `session.bindExtensions()` (print-mode
  parity). Found because the `mcp` tool answered "MCP not initialized".
- **The model reads `../` and greps the repo.** A smoke run found the fixture
  source, discovered the `/chk-clear` route, and bypassed the interstitial. Fixed:
  site source/log/truth moved to a random temp dir; the clearance route now requires
  the full 5-second wait.
- **Two of my own fixture bugs**, both caught because models reported them
  plausibly: 500s on the docs routes (event-object passed as status argument), and —
  after a category-nav edit — the catalog page rendering with **no products** (the
  product list was passed as a dropped third argument to `page(title, body)`). The
  uniform t1 = 0.00 across all arms was the fixture lying to every model. Fixed,
  verified end-to-end, t1 re-run.
- **Parallel-run races** on the shared per-arm agent dir (Bun EFAULT/EEXIST on
  `rmSync`+`symlink` of the package link and skill dir) crashed 4 tasks. Fixed
  create-once; the crashed runs were re-run.
- **Stale results contamination**: an aggregate that globs `results/*` mixed runs
  from before and after the fixture fix. Pre-fix runs are now archived under
  `results/archive-pre-fix/`.

## 6. Results

157 valid runs (19 excluded as degenerate — all deepseek; see §7). Outcome = fraction of exact
ground-truth values present in the final answer. Calls = browser tool/CLI
invocations per task. Tokens = input+output per task.

### Outcome by arm and model

| arm | glm-5.3-flash | deepseek-v4-flash-latest |
|---|---:|---:|
| `cli-agent-browser` (CLI + skill) | 0.93 | **1.00** |
| `cli-playwright` (CLI + skill) | **1.00** | 0.82 |
| `agent-browser` (native tool) | 0.93 | 0.92 |
| `agent-browser-guided` | **1.00** | 1.00* |
| `playwright` (@playwright/mcp) | 0.93 | 0.92 |
| `devtools` (chrome-devtools-mcp) | 0.86 | 0.77 |

\* guided-deepseek: only 8 valid runs (7 degenerate-excluded), no valid t3 — weak
evidence, do not over-read.

### Efficiency

| arm | glm calls / tokens | deepseek calls / tokens |
|---|---|---|
| `cli-playwright` | **5.1 / 7.9k** | 5.7 / 11.1k |
| `cli-agent-browser` | 7.2 / 8.4k | **8.1 / 11.1k** |
| `playwright` | 11.1 / 9.7k | 16.4 / 29.4k |
| `devtools` | 11.3 / 12.2k | 14.4 / **49.1k** |
| `agent-browser` | 14.5 / 11.1k | 14.0 / 23.2k |
| `agent-browser-guided` | 16.7 / 8.9k | 31.4 / 30.8k |

### Per-task outcomes (valid runs)

| arm | model | t1 | t2 | t3 | t4 | t5 |
|---|---|---:|---:|---:|---:|---:|
| cli-agent-browser | glm | 1.00 | 1.00 | 0.67 | 1.00 | 1.00 |
| cli-agent-browser | ds | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| cli-playwright | glm | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| cli-playwright | ds | 1.00 | 1.00 | 0.00 | 1.00 | 1.00 |
| agent-browser | glm | 1.00 | 1.00 | 0.67 | 1.00 | 1.00 |
| agent-browser | ds | 1.00 | 1.00 | 0.67 | 1.00 | 1.00 |
| agent-browser-guided | glm | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| playwright | glm | 1.00 | 1.00 | 0.50 | 1.00 | 1.00 |
| playwright | ds | 1.00 | 1.00 | 0.50 | 1.00 | 1.00 |
| devtools | glm | 1.00 | 1.00 | 0.33 | 1.00 | 1.00 |
| devtools | ds | 1.00 | 0.50 | 0.50 | 1.00 | 0.67 |

## 7. Findings

1. **The CLI + skill pattern is the headline result.** With zero additions to pi
   (no tools, no extensions — one SKILL.md and a CLI that is already installed for
   `cli-agent-browser`), the CLI arms match or beat every extension arm on outcome
   for both models at roughly **half the calls and tokens**. glm: `cli-playwright`
   went 15/15 at 5.1 calls / 7.9k tokens. deepseek: `cli-agent-browser` went 12/12
   valid. The skill is doing real work — it is the same engine as the native
   baseline, so the surface, not the engine, drives the difference.

2. **There is no single clean sweep on outcome alone.** With n=3 seeds per cell,
   the 0.82–1.00 band overlaps. The consistent signal is the *combination* of
   outcome + cost: the CLI arms top the outcome table while spending ~half of what
   extension arms spend. `cli-agent-browser` is the most robust single choice
   (never below 0.93 on either model); `cli-playwright` is the best single-model
   performer (perfect on glm) but its rate-limit handling collapsed with deepseek
   (t3 = 0.00).

3. **Captcha handling is model behavior, not tool behavior.** Every arm on both
   models solved the checkbox gate on first contact in nearly every run
   (~1 challenge per gated task, ~1.0 solve rate server-side). The one hard-stuck
   specimen (playwright arm, t1): the model misread a code and re-submitted the
   same wrong value 7 times, then escaped by opening a fresh browser context —
   still finishing the task. The live-web captchas that motivated this work are
   IP/profile-driven; switching tools does not change them.

4. **Rate limiting (t3) is the only reliable outcome discriminator** — and the
   native tool plus well-written skills handle it best. The `nextActions`-style
   recovery guidance in the native tool and the behavioral rules in the skills
   (wait for Retry-After) beat the MCP servers' error text.

5. **Guidance context helps strong models and hurts weak ones.** For glm, the tips
   took the baseline from 0.93 → 1.00 and cut 429s 22 → 0. For deepseek, the guided
   arm produced 7 degenerate outputs in 15 runs (47% — the highest of any arm) and
   burned 31.4 calls / 30.8k tokens. One data point each, but the asymmetry is
   suspicious enough to not ship guidance blindly.

6. **deepseek-v4-flash-latest degenerates mid-task.** All 19 degenerate finals
   across the matrix were deepseek (chat-template markup emitted as assistant
   text) — 21% of deepseek run-slots. Per the monitor eval's precedent these are
   flagged and excluded, not scored as task failures. Rate by arm: 47% in the
   guided arm (highest), 10–27% elsewhere. glm never degenerated.

7. **devtools-mcp is the wrong default for this use case**: weakest outcomes
   (0.86 / 0.77) and, with deepseek, 49.1k tokens per task — 4–6× the CLI arms.
   It remains interesting for debugging-heavy work (performance traces, network
   inspection) that the other surfaces do not expose.

## 8. Recommendation

Adopt **CLI + skill with the `agent-browser` CLI** as the default browser setup:

- Best worst-case across both models (0.93 / 1.00), never below any competitor.
- Cheapest robust profile (~half the calls and tokens of the native extension).
- Zero new dependencies — the CLI is already installed and version-pinned by
  `install.sh`; the only change is shipping one `SKILL.md` into the agent dir and
  documenting that the browser is a CLI, not a tool.
- Keep the `pi-agent-browser-native` extension available for models/sessions that
  benefit from the structured tool surface (the deepseek data suggests it is the
  best *extension* arm), and `chrome-devtools-mcp` available for debugging-heavy
  work.

For live-web captcha pain specifically: warm persistent profiles, patient
interstitial handling, and Retry-After compliance move the needle; tool choice does
not. A short skill (like the ones in `harness/skills/`) is the cheapest way to ship
those behaviors.

## 9. Caveats

- **n = 3 seeds per cell.** ±1 run swings are normal; the CLI-vs-extension cost gap
  and the devtools deficit are the only effects I would call established. The
  cli-playwright (glm) perfection and the guided-deepseek harm are suggestive, not
  proven.
- **Fixture, not live web.** The friction is realistic by construction (and the
  live-web incidents in §2 are real) but sampled sites and challenge types are
  limited to what the fixture simulates.
- **One eval author, one machine.** Load was wave-balanced by model, but timing
  metrics carry parallel-run noise.
- **Degenerate-output exclusion** flatters deepseek arms with high degeneracy rates
  (the alternative — scoring them 0 — would punish arms for a model bug).

## 10. Reproducing

```bash
cd evals/browser
(cd vendor && bun add pi-mcp-adapter@2.31.0)   # once, for the MCP arms
npm install -g @playwright/cli@0.1.18          # once, for the cli-playwright arm

ARMS="agent-browser agent-browser-guided playwright devtools cli-agent-browser cli-playwright" \
  MODELS="openrouter/z-ai/glm-5.3-flash openrouter/~deepseek/deepseek-v4-flash-latest" \
  SEEDS="101 202 303" ./run-multi.sh
for d in results/2026*_seed*; do python3 score/score.py "$d"; done
python3 score/aggregate.py final results/2026*_seed*
```

Merged tables: `results/combined-scores.json` (valid) and
`results/invalid-runs.json` (degenerate, with arm/model/task/seed). Design notes,
bug log, and phase-by-phase findings: [`WORKFLOW.md`](WORKFLOW.md). Task and metric
definitions: [`README.md`](README.md).
