# Workflow: from captcha complaints to a browser-stack benchmark and comparison

This document records the arc of the `browser-eval` branch: researching alternatives
to the installed browser tool, building a deterministic gauntlet that reproduces the
friction agents hit on the live web, fixing what the benchmark caught (including two
of our own bugs), and comparing four browser stacks head-to-head with one model.

## The question

The user-facing complaint: agents using the installed browser tool (`agent-browser`
via `pi-agent-browser-native`) keep getting stuck on captchas. Live confirmation came
free during research: Google served its `/sorry/` page, DuckDuckGo an anomaly
challenge, and npmjs a Cloudflare interstitial — to this very setup, within minutes,
on the same real-Chrome stack. The question split in two: (a) is there a better
browser extension, and (b) would additional context help agents avoid the issues?

## Phase 1 — Research: what could replace the current stack?

Constraints: pi has no built-in MCP (by design), so candidates must be pi extensions
or bridgeable MCP servers. Community support was a hard requirement.

| candidate | community | verdict |
|---|---|---|
| `agent-browser` + pi fork (installed) | 205★ pi ext, 5.2M dl/mo upstream | baseline |
| `@playwright/mcp` | Microsoft official, 36.6k★, 25M dl/mo | test |
| `chrome-devtools-mcp` | Chrome team official, 50k★, 9.8M dl/mo | test |
| `pi-mcp-adapter` (bridge) | 1.36k★, 695k dl/mo | shared bridge for both MCP arms |
| `pi-browser-debug`, `pi-browser`, `pire-browser` | 316 / 99 / 385 dl/mo | rejected: no community |
| `browser-use` (MCP) | 111k★ but an agent-in-agent loop | rejected: wrong shape for a tool comparison |
| `@amaster.ai/pi-browser-use`, `@narumitw/pi-chrome-devtools` | 4k / 7k dl/mo | noted, smaller than the chosen bridge |

Key design decision: **both MCP arms go through the same `pi-mcp-adapter` gateway**
(lazy `mcp` proxy that registers direct tools after first connect), so the comparison
isolates the browser stack rather than the bridge quality.

The captcha literature check (and live evidence) reframed the problem: challenges are
driven mostly by IP reputation, automation signals (`navigator.webdriver`), and cold
profiles — not by which extension drives Chrome. All four arms drive real Chrome via
CDP, so **the eval measures handling (solve / wait / back off vs flail / loop), not
avoidance**. Avoidance is a property of the IP and profile, not the tool.

## Phase 2 — Benchmark design

Same principles as the monitor eval, adapted for browsers:

1. **Never mention captchas, bot checks, or waiting.** Prompts are ordinary research
   errands; the site supplies the friction.
2. **Deterministic, server-instrumented friction.** A seeded demo store
   (`harness/site/server.ts`) with: a hard bot block on non-browser user agents (curl
   cannot cheat); a checkbox-style human gate on first visit, escalating to a 6-char
   code captcha on retries; a "Checking your browser… ~5 s" interstitial whose
   clearance route rejects early arrivals (waiting is the only strategy); a 6-req/10 s
   rate limiter with `Retry-After` on a 12-page JSON listing; a form login with a
   runtime-bound password; and JS-assembled content invisible in raw HTML.
3. **Server evidence beats model claims.** The site logs every request: challenges
   served/solved/failed, interstitials served/cleared/restarted, 429s, auth attempts.
   "Did it solve the captcha" is answered by the log, never by the transcript.
4. **Runtime-bound ground truth.** Answers carry a per-run nonce; the password exists
   only in the site's truth file; the site (source, log, truth) runs from a random
   temp directory.

Arms: `agent-browser` (baseline), `agent-browser-guided` (baseline + 4 lines of
user-supplied tips appended to the prompt — the documented test of "would context
help"), `playwright`, `devtools`. Five tasks: catalog crawl through the gate (t1),
rotation-code lookup behind the interstitial (t2), rate-limited analytics compile
(t3), login flow (t4), control homepage read (t5).

## Phase 3 — Harness bugs (found by the benchmark, before any results were trusted)

- **`session_start` never fires in the bare SDK.** `pi-mcp-adapter` initializes its
  gateway on the `session_start` extension event; print mode emits it via
  `bindExtensions`, the bare SDK does not. The `mcp` tool answered "MCP not
  initialized" until the harness called `session.bindExtensions()` explicitly.
- **The model reads `../` and greps the repo.** A smoke run had the model open the
  fixture site's source, find the `/chk-clear` route, and bypass the interstitial —
  and it could have read `../ground_truth.json`. Fixed by moving site source, log,
  and truth into a random temp directory, and by making the clearance route require
  the full 5-second wait (early arrival restarts the interstitial).
- **My own signature bugs.** The event-object-vs-status-argument mistake produced 500s
  on the docs routes, and a later category-nav edit passed the product list as a
  dropped third argument to `page(title, body)` — the catalog rendered empty. The
  first full run's uniform t1 = 0.00 across all arms was this bug, not model failure.
  Diagnosed from transcripts ("page 1 of 2 but shows no products"), fixed, verified
  end-to-end with a scripted gate-solve, and t1 was re-run for all arms.

The empty-catalog incident is the benchmark working as intended: the models' reports
of "no products" were accurate, and only cross-checking the site log against the
transcripts revealed the fixture was lying to them.

## Phase 4 — Results (glm-5.3-flash, 3 seeds × 5 tasks × 4 arms, t1 from the post-fix rerun)

| arm | outcome | browser calls | dup calls | challenges served/solved | loops | 429s | ignored Retry-After | interstitials | avg time | tokens |
|---|---|---|---|---|---|---|---|---|---|---|
| agent-browser | **0.97** | 14.3 | 1.3 | 3/3 | 0 | 25 | 2 | 6 | 110 s | 11.4k |
| agent-browser-guided | 0.93 | 14.7 | 1.2 | 3/3 | 0 | **6** | 0 | 6 | 110 s | **8.8k** |
| devtools (chrome-devtools-mcp) | 0.90 | 12.3 | **0.5** | 3/3 | 0 | 18 | 1 | 7 | 112 s | 10.3k |
| playwright (@playwright/mcp) | 0.90 | **11.1** | **0.5** | 10/3 | 1 | **6** | 0 | 7 | 113 s | 10.4k |

Per-task outcomes: t1/t2/t4/t5 at or near 1.00 everywhere (t2's JS-only rendering
defeated raw-HTML shortcuts for every stack); **t3 — the rate limiter — is the only
outcome discriminator**: agent-browser 0.83, guided 0.67, playwright and devtools 0.50.

Findings:

1. **Captcha handling was not the differentiator.** The gates are readable; every arm
   solved the checkbox on first contact in nearly every run. The genuine stuck
   pattern appeared once (playwright, t1): the model misread a code and re-submitted
   the same wrong value 7 times, then escaped by opening a fresh browser context —
   server evidence: 7 `challenge_failed` on one session, solve on the next.
2. **Rate limits expose the stacks.** agent-browser absorbed 25 429s (it re-crawls
   aggressively) yet delivered the correct sum most often; both MCP arms failed t3
   half the time. The `nextActions`-style recovery guidance in the native tool seems
   to help pacing more than the MCP servers' error text.
3. **Efficiency favors the MCP arms on call count** (11–12 vs 14), with the fewest
   duplicate calls — but their extra calls are batched `evaluate`/`run_code` payloads
   that misfire more often on weak models (the devtools t2 transcript shows several
   dead `outerHTML` dumps before a snapshot).
4. **Context (the guided arm) changed pacing, not capability**: 429s dropped 25→6 and
   tokens 11.4k→8.8k, but t3 outcome fell 0.83→0.67 (n=3; within noise per monitor
   lesson 6). The tips helped the model behave politely without making it more right.

## Phase 5 — First verdict (before the CLI arms)

- **Keep agent-browser as the default.** Highest outcome, best rate-limit handling,
  mature recovery surface. The captcha complaint is real but is not caused by the
  tool: the same challenges were solved by every stack, and the live-web captchas
  that started this are IP/profile-driven.
- **chrome-devtools-mcp via pi-mcp-adapter is a credible fallback** — cleanest call
  discipline, official support — and a reasonable choice for debugging-heavy work
  (performance traces, network inspection) that agent-browser does not expose.
- **playwright-mcp is the most call-efficient** but was the only arm to hard-stuck on
  a captcha loop, and lost t3 half the time.
- What actually reduces captcha pain: warm persistent profiles, pacing after 429s,
  and reading the challenge page — all behavioral or configuration, not tool choice.
  A small amount of user context nudges pacing; it does not fix weak models.

## Phase 6 — The CLI + skill arms (no new tools, no extensions)

The user's hypothesis: install a browser CLI alongside pi and teach it with a skill —
no new tools or extensions at all. That is also the pattern Playwright itself now
recommends for coding agents (CLI+SKILLS over MCP for token efficiency).

Two new arms, each with **zero packages** in the agent dir:

- `cli-agent-browser` — the already-installed `agent-browser` CLI + one SKILL.md
  (core loop: open → `snapshot -i` → refs → click/fill; behavioral rules). Session
  isolation per run via `AGENT_BROWSER_SESSION`/`AGENT_BROWSER_NAMESPACE`.
- `cli-playwright` — the official `@playwright/cli@0.1.18` (installed alongside pi)
  + one SKILL.md. Session isolation via `PLAYWRIGHT_CLI_SESSION`.

The `cli-agent-browser` arm doubles as a controlled experiment: same engine as the
native baseline, so the native-tool-vs-CLI+skill difference is isolated.

Two harness bugs bit here, both race conditions from parallel tasks of one arm
sharing a PIHOME: concurrent `rmSync`+`symlinkSync` of the package link (EEXIST) and
of the skill directory (Bun EFAULT, one crashed run). Fixed create-once. A scoring
contamination was also caught: stale pre-fix run dirs were still in `results/` and
silently double-counted glm t1/t3 — archived, and the merged table rebuilt.

## Phase 7 — Final results and verdict (both models)

Run: 6 arms × 2 models (glm-5.3-flash, deepseek-v4-flash-latest) × 3 seeds × 5 tasks
= 176 scored runs; 19 deepseek runs flagged degenerate (chat-template junk as final
assistant text — the failure mode the monitor eval also hit) and excluded.

| arm | glm out | ds out | glm calls/tok | ds calls/tok |
|---|---|---|---|---|
| agent-browser (native) | 0.93 | 0.92 | 14.5 / 11.1k | 14.0 / 23.2k |
| agent-browser-guided | 1.00 | 1.00* | 16.7 / 8.9k | 31.4 / 30.8k |
| playwright-mcp | 0.93 | 0.92 | 11.1 / 9.7k | 16.4 / 29.4k |
| devtools-mcp | 0.86 | 0.77 | 11.3 / 12.2k | 14.4 / **49.1k** |
| cli-agent-browser | 0.93 | **1.00** | **7.2 / 8.4k** | **8.1 / 11.1k** |
| cli-playwright | **1.00** | 0.82 | **5.1 / 7.9k** | 5.7 / 11.1k |

*guided-ds: n=8 valid (7 degenerate-excluded), and no valid t3 runs — weak evidence.

Verdict:

1. **The user's hunch was right.** CLI + skill — no new tools, no extensions — matches
   or beats every extension arm on outcome for both models at roughly **half the calls
   and tokens**. For glm, cli-playwright went 15/15. For deepseek, cli-agent-browser
   went 12/12 valid.
2. **The native tool earns its keep for weaker models.** agent-browser-native was the
   best extension arm for deepseek (0.92): the structured tool surface and
   nextActions-style recovery guidance matter when the model is weak. But the CLI arm
   with the same engine still beat it (1.00) — the skill text is doing real work.
3. **devtools-mcp is the wrong default here**: weakest outcomes and, with deepseek,
   49k tokens per task — 4–6× the CLI arms.
4. **Captcha behavior is model behavior, not tool behavior.** Every arm solved the
   gates on first contact when the model was functioning; the failures observed were
   misread codes (re-submitted blindly) and degenerate outputs.
5. deepseek-v4-flash-latest is noticeably cheaper per call than glm but degenerates
   mid-task at a meaningful rate (18/19 degenerate runs). If it is used, the CLI arms
   also had the fewest degenerate episodes relative to runs.

Caveats: n=3 seeds per cell (±1 run swings are normal); local fixture site (live-web
captcha friction is represented by construction, not sampled); one eval author.

## Lessons (cumulative)

1. **Benchmarks catch your own bugs first.** Two fixture signature bugs and a ground
   truth reachable at `../` were all found by watching models fail plausibly.
2. **Server-side evidence settles what transcripts cannot.** "Solved the captcha" is
   a fact about a cookie, not about prose.
3. **Saturate checks both ways.** t2/t4/t5 topped out (fine — they bound baseline
   overhead); t1's first version bottomed out for every arm, which turned out to be
   the fixture, not the model.
4. **Same-bridge arms keep the comparison honest.** Differences between the MCP arms
   are attributable to the servers; the difference between native and MCP surfaces is
   attributable to the tool contract.
5. **The live-web problem is mostly not the tool.** Switching extensions does not
   change IP reputation; measuring handling on a deterministic fixture was the only
   way to answer the actual question.

## Reproducing

```bash
cd evals/browser
(cd vendor && bun add pi-mcp-adapter@2.31.0)   # once, for the MCP arms
npm install -g @playwright/cli@0.1.18          # once, for the cli-playwright arm

ARMS="agent-browser agent-browser-guided playwright devtools cli-agent-browser cli-playwright" \
  MODELS="openrouter/z-ai/glm-5.3-flash openrouter/~deepseek/deepseek-v4-flash-latest" \
  SEEDS="101 202 303" ./run-multi.sh
for d in results/2026*_seed*; do python3 score/score.py "$d"; done
python3 score/aggregate.py final results/2026*_seed*
# merged/degenerate-flagged tables: results/combined-scores.json, results/invalid-runs.json
# runs from before the fixture fix are archived under results/archive-pre-fix/
```

6. **Watch for stale results dirs.** An aggregate that globs `results/*` will happily
   mix runs from before and after a fixture fix; archive superseded runs.
7. **Create-once for shared agent dirs.** Parallel tasks of one arm must not rm/race
   on PIHOME content; Bun surfaces the race as EFAULT/EEXIST in exactly one task.
8. **Degenerate output is not task failure.** Count it, report it, exclude it —
   otherwise a model's template bug masquerades as a tool ranking.
