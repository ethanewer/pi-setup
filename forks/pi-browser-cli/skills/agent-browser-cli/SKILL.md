---
name: agent-browser-cli
description: Drive a real Chrome browser from bash with the agent-browser CLI. Use for any task that needs a web page opened, read, filled, clicked, screenshotted, or otherwise interacted with, including login flows and scraping rendered pages. Prefer it over curl/wget for sites that check for bots.
---

# Browser automation with agent-browser (CLI)

`agent-browser` is installed on PATH and drives a real (headless) Chrome. Invoke it
from bash like any other command. All state lives in a named browser session; the
default session is fine for one task at a time. For parallel browsers, give each its
own session with `--session <name>` (or `AGENT_BROWSER_SESSION=<name>`).

## Core loop

1. Open a page and get interactive element refs:

```bash
agent-browser open "https://example.com"
agent-browser snapshot -i          # interactive elements with @refs (buttons, links, inputs)
```

2. Read page content:

```bash
agent-browser get text "main"            # text of a CSS selector
agent-browser get text "body"            # full visible text of the page
agent-browser find "pricing"             # find text/roles in the snapshot, with refs
agent-browser get title
agent-browser get url
```

3. Interact using the @refs from the last snapshot:

```bash
agent-browser click @e12
agent-browser fill @e7 "search text"
agent-browser select @e9 "option-value"
agent-browser press Enter
```

4. Re-snapshot after every navigation or mutation — refs go stale:

```bash
agent-browser snapshot -i
```

## Useful extras

- `agent-browser eval "document.title"` — run JS in the page (for things the
  snapshot does not show, e.g. content rendered only after a delay).
- `agent-browser screenshot` — save a PNG when visual layout matters.
- `agent-browser requests` — recent network requests.
- Batch independent reads in one call with `batch` (JSON lines on stdin) when
  the flow is obvious; otherwise step-by-step is fine.
- `agent-browser close` when finished.
- For the full reference that always matches the installed CLI version:
  `agent-browser skills get core` (add `--full` for the complete command
  reference). `agent-browser skills list` shows specialized skills (Electron
  apps, Slack, QA dogfooding).

## Behavior rules

- Headless by default; do not pass --headed.
- If a page shows a bot check or CAPTCHA, read what it asks and complete it
  (type the displayed code, tick the checkbox). Retrying blindly does not help.
- If a page says it is "checking your browser", wait for the stated duration
  (typically ~5 seconds), then reload once. Do not refresh rapidly — early
  reloads restart the check.
- On HTTP 429, wait the number of seconds in the Retry-After header before the
  next request to that path.
- Refs are only valid for the latest snapshot; after any navigation take a new
  `snapshot -i` before clicking or filling.
