# pi-cost

First-party extension, no upstream. Registers `/cost`: live OpenRouter rates for
the pinned models, in dollars per million tokens.

```
  deepseek/deepseek-v4-flash-0731  $0.07 in / $0.18 out / $0.02 cache read
  deepseek/deepseek-v4-pro-0813    $0.58 in / $1.74 out / $0.02 cache read
  deepseek/deepseek-v4.1-flash     $0.15 in / $0.60 out / $0.003 cache read
  ...
```

Design points:

- **The pinned set comes from the session scope** (`ctx.scopedModels`, i.e. the
  `enabledModels` list install.sh writes), filtered to provider `openrouter`.
  Adding a model to `MODEL_SCOPE` in `lib/install.mjs` is enough for it to
  appear here; nothing in this extension names a model. OpenAI subscription
  models are excluded by the same filter — they are not billed through
  OpenRouter. When no scope is set, every available OpenRouter model is listed.
- **Rates are fetched at command time** from OpenRouter's public
  `/api/v1/models` endpoint (no key needed), so they are current, not up to
  four hours stale like Pi's cached catalog. While the fetch runs, the editor
  slot shows a bare spinner line — "⠋ Fetching latest costs…" — with no border
  frame; escape cancels it. On fetch failure (not cancellation) it falls back
  to the catalog metadata Pi's cost accounting uses and says so in the header.
- **Per-token to per-Mtok conversion** is done here; OpenRouter prices in
  per-token strings. Zero components are omitted; cache write precedes cache
  read when charged. Usage-window pricing (V4.1 Flash's weekday/weekend tiers,
  windows as HHMM times by UTC day) is resolved against the current UTC time:
  the row shows the rates in force when the command runs — peak-window pricing
  during a peak window, off-peak otherwise — one line per model, no annotation.
- **No model calls** — the command is free to run. Like the built-in `/model`, it is
  interactive-only: print mode (`pi -p`) sends leading-slash prompts to the model
  instead of executing them, and `ctx.ui.notify` has no print-mode surface.

`rates.ts` is pure and unit-tested in `tests/cost-command.test.ts`.