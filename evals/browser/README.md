# browser-bench — how well do agent browser stacks handle a hostile (but fair) web?

Behavioral eval for the browser tooling of this setup. It measures what the monitor
eval measures for watchers, but for browsers: **can the agent get real work done
through a website that checks for bots — and at what cost in calls, time, and
tokens — and where does it get stuck?**

## The question

The user-facing problem: agents using the current browser tool (`agent-browser` via
`pi-agent-browser-native`) keep getting stuck on captchas and bot checks. Live sites
confirm the friction is real (during development, Google served its `/sorry/` page,
DuckDuckGo an anomaly challenge, and npmjs a Cloudflare interstitial to this very
setup). This benchmark makes that friction deterministic and measurable instead of
depending on the mood of Cloudflare.

## Arms

| arm | browser stack | bridge |
|-----|---------------|--------|
| `agent-browser` | upstream `agent-browser` CLI → real Chrome (the installed fork, pinned 0.35.0) | native pi tool |
| `agent-browser-guided` | same as above, plus 4 lines of user-supplied tips appended to the prompt (documented deviation — measures the value of context) | native pi tool |
| `playwright` | [`@playwright/mcp@0.0.79`](https://github.com/microsoft/playwright-mcp) (Microsoft official, 36k★) headless, per-run profile | [`pi-mcp-adapter@2.31.0`](https://github.com/nicobailon/pi-mcp-adapter) lazy MCP gateway |
| `devtools` | [`chrome-devtools-mcp@1.8.0`](https://github.com/ChromeDevTools/chrome-devtools-mcp) (Chrome team official, 50k★) headless, per-run profile | same `pi-mcp-adapter` gateway |

Both MCP arms share the same bridge so the comparison isolates the browser stack.
Every arm drives a real (headless) Chrome; the arms differ in the tool surface the
model sees and the automation library behind it.

## The fixture site

`harness/site/server.ts` is a seeded demo store whose difficulties are the point:

- **Hard bot block** — non-browser user agents (curl, python-requests) get 403, so
  the browser tool is the only way through.
- **Human gate** — catalog/product pages serve an interstitial on first visit per
  session: a checkbox-style check, then a 6-character code captcha on any retry.
  Solving issues a clearance cookie. The code is plain text on the page; the check
  is solvable, by design — the question is whether the agent reads and completes it
  or flails.
- **Browser-check interstitial** — the security docs pages hold a "Checking your
  browser… ~5 s" page with a JS countdown; the clearance route refuses early
  arrivals, so waiting is the only strategy.
- **Rate limiter** — `/api/list` allows 6 requests per 10 s per session, then 429
  with `Retry-After: 5`. The listing has 12 pages, so a fast crawler *will* hit it.
- **Login flow** — form auth with a runtime-bound password (see ground truth).
- **JS-only content** — the rotation code is assembled by CSS/JS from data
  attributes, invisible in raw HTML, so fetching the source does not answer t2.

Everything the site does is logged per request to `sitelog.jsonl` — challenges
served/solved/failed, interstitials served/cleared/restarted, 429s, auth attempts.
**The site log is the ground truth for all friction metrics**, not the model's
claims. Ground-truth answer values carry a per-run nonce and the whole site (source,
log, truth) runs from a random temp directory, after a model demonstrated during
development that it reads `../` and greps the repo when a task resists it.

## Tasks

| task | scenario | friction under test |
|------|----------|---------------------|
| t1 | find the most expensive product across a 3-category catalog | checkbox + code captcha gate, pagination, category discovery |
| t2 | find the monthly rotation confirmation code in the security docs | browser-check interstitial (must wait), JS-only rendering |
| t3 | compile the analytics listing (`/api/list`, 12 pages) | 429 rate limiting; Retry-After compliance |
| t4 | sign in and report the latest order | form login, second interstitial behind auth |
| t5 | control: read hours + support email off the homepage | none — measures baseline overhead per stack |

Task prompts describe ordinary goals; none mentions captchas, bot checks, or
waiting. Prompts and tasks are identical across arms except the documented
`agent-browser-guided` deviation.

## Metrics

- **Outcome** — exact runtime-bound values in the final answer (SKU, price, code,
  sum, order number), scored against `ground_truth.json`.
- **Friction handling (server-evidence)** — challenges served vs solved vs failed;
  challenge loops (repeated gate hits without solving); interstitial restarts
  (impatience); 429s received vs `Retry-After` violations (requests <4 s after a 429).
- **Efficiency (transcript)** — browser tool calls, bash/read calls (escape
  attempts), duplicate identical calls, unique URLs visited, turns, tokens, wall time.
- **Getting stuck** — challenge loops, ignored Retry-After, curl bypass attempts
  (visible server-side as `bot_blocked`), budget exits.

## Results (glm-5.3-flash, 3 seeds × 5 tasks × 4 arms)

See [`WORKFLOW.md`](WORKFLOW.md) for the full story. Summary (t1 from the post-fixture-fix
rerun; merged table in `results/combined-scores.json`):

| arm | outcome | browser calls | challenges served/solved | 429s | tokens |
|---|---|---|---|---|---|
| `agent-browser` (baseline) | **0.97** | 14.3 | 3/3 | 25 | 11.4k |
| `agent-browser-guided` | 0.93 | 14.7 | 3/3 | **6** | **8.8k** |
| `devtools` (chrome-devtools-mcp) | 0.90 | 12.3 | 3/3 | 18 | 10.3k |
| `playwright` (@playwright/mcp) | 0.90 | **11.1** | 10/3 | **6** | 10.4k |

The rate-limited task (t3) is the only outcome discriminator (0.83 / 0.67 / 0.50 / 0.50).
Captcha gates were solved on first contact by every arm; the one hard-stuck loop
occurred on playwright (misread code re-submitted 7×, escaped via a fresh context).

## Usage

```bash
cd evals/browser
ARM=agent-browser SEED=101 ./run.sh          # one arm, one seed, all 5 tasks in parallel
python3 score/score.py results/latest        # per-run scores
python3 score/aggregate.py results/latest

ARMS="agent-browser agent-browser-guided playwright devtools" SEEDS="101 202 303" ./run-multi.sh
python3 score/aggregate.py browser results/*_agent-browser_seed* \
  results/*_agent-browser-guided_seed* results/*_playwright_seed* results/*_devtools_seed*
```

Keys come from the ambient environment (`OPENROUTER_API_KEY`), as in the monitor
eval. The default model is `openrouter/z-ai/glm-5.3-flash`.

## Notes

- The MCP arms need `vendor/node_modules` (`cd vendor && bun add pi-mcp-adapter@2.31.0`).
- `pi-mcp-adapter` initializes on the `session_start` extension event; the harness
  calls `session.bindExtensions()` (print-mode parity) — the bare SDK never emits it.
- Each run gets its own site port, nonce, and (MCP arms) browser profile directory,
  so parallel runs cannot share cookies or challenge state.
- Traces from the MCP gateways land in `work/.pi/mcp-traces/` for debugging.
