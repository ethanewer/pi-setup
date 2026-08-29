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

## Phase 5 — Verdict

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

## Lessons

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
(cd vendor && bun add pi-mcp-adapter@2.31.0)   # once
ARMS="agent-browser agent-browser-guided playwright devtools" SEEDS="101 202 303" ./run-multi.sh
for d in results/*_seed*; do python3 score/score.py "$d"; done
python3 score/aggregate.py results/*_seed*
# t1 was re-run after the fixture fix:
#   results/*t1rerun_*/t1 hold the valid t1 scores; results/combined-scores.json
#   is the merged per-run table used for the tables above.
```
