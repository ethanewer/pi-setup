---
name: playwright-cli
description: Drive a real Chrome browser from bash with the playwright-cli. Use for any task that needs web pages opened, read, or interacted with.
---

# Browser automation with playwright-cli

`playwright-cli` is installed on PATH and drives a real (headless) Chromium via
Playwright. Invoke it from bash like any other command. Browser state lives in a
named session; this environment pre-selects one via `PLAYWRIGHT_CLI_SESSION`, so
plain invocations just work and cookies persist between calls.

## Core loop

1. Open the page, then capture a snapshot to get element refs:

```bash
playwright-cli open "https://example.com"
playwright-cli snapshot          # page as YAML with refs like e12, e13
```

2. Read page content:

```bash
playwright-cli find "pricing"    # search the snapshot for text, with refs + context
playwright-cli eval "() => document.body.innerText"   # visible text
playwright-cli eval "() => document.title"
```

3. Interact using refs from the latest snapshot:

```bash
playwright-cli click e12
playwright-cli fill e7 "search text"
playwright-cli select e9 "option-value"
playwright-cli check e3
playwright-cli press Enter
```

4. Re-snapshot after every navigation or mutation — refs go stale:

```bash
playwright-cli snapshot
```

## Useful extras

- `playwright-cli goto <url>` — navigate the existing tab.
- `playwright-cli requests` / `playwright-cli response-body <n>` — inspect network.
- `playwright-cli console` — page console messages (useful when a page looks empty).
- `playwright-cli screenshot` — save a PNG when visual layout matters.
- `playwright-cli eval "() => location.href"` — current URL.
- `playwright-cli close` when finished.

## Behavior rules

- Headless by default; do not pass --headed.
- If a page shows a bot check or CAPTCHA, read what it asks and complete it
  (type the displayed code, tick the checkbox). Retrying blindly does not help.
- If a page says it is "checking your browser", wait ~5 seconds, then reload or
  goto the URL once. Do not refresh rapidly.
- On HTTP 429, wait the number of seconds in the Retry-After header before the
  next request to that path.
- Refs are only valid for the latest snapshot; after any navigation take a new
  `snapshot` before clicking or filling.
- If a page renders blank, check `console` and `eval` the body text before
  concluding anything.
