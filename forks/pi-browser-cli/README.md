# pi-browser-cli

First-party, skills only: no extensions and no tools. Ships the `agent-browser-cli`
skill, which teaches the agent to drive the `agent-browser` CLI (installed and
version-pinned by `install.sh`) from bash. This package is how the browser is exposed
by default: a CLI plus a skill, not a Pi tool.

## Why a CLI and a skill instead of the browser extension

`evals/browser/` on the `browser-eval` branch benchmarked six browser surfaces —
the native `agent_browser` tool, the same tool plus prompt guidance, two MCP servers
(`@playwright/mcp`, `chrome-devtools-mcp`) behind a shared bridge, and two CLI+skill
arms (`agent-browser` CLI, `@playwright/cli`) — across two models, three seeds, and
five tasks on a seeded fixture site with deterministic, server-instrumented friction
(bot block, checkbox/code captcha, timed browser-check interstitial, rate limiter
with `Retry-After`, form login, JS-only content). See that branch's
`evals/browser/REPORT.md` for the full writeup and raw results.

Outcome: the CLI+skill arms matched or beat every extension arm on task outcome for
both models at roughly half the browser calls and tokens. `agent-browser` was chosen
over `@playwright/cli` because it never fell below 0.93 on either model (the
Playwright CLI's rate-limit handling collapsed on one of them), and because it is the
engine the setup already installs and pins. The skill text is what carries the
difference: the `cli-agent-browser` eval arm used this same engine, so the surface,
not the engine, drove the result.

Two things the fixture could not measure and that motivated the skill's behavior
rules anyway: live-web captchas are driven by IP reputation, automation signals, and
profile state, not by which code drives Chrome. What an agent can control is
*handling* — read the challenge and complete it, wait out "checking your browser"
interstitials instead of refreshing, and honor `Retry-After` on 429s. Those three
rules are in the skill.

## What about the native tool surface

`pi-agent-browser-native-safe` remains in `forks/` and stays installed under
`~/.pi/agent/local/`, but is no longer loaded by default; the eval found the CLI
surface cheaper and at least as accurate on both models tested. To load it again
(the structured tool, `nextActions` recovery guidance, and its bash guard that
blocks direct CLI launches from the agent), install with:

```bash
PI_SETUP_BROWSER_TOOL=1 ./install.sh
```

The eval's own caveat applies: with a weak model the native tool was the best
*extension* arm, so a setup that runs only weak models may prefer it.

For debugging-heavy work (performance traces, network inspection), the eval points at
`chrome-devtools-mcp` behind an MCP bridge; it is not installed by this setup.
