# pi-cost

First-party extension, no upstream. Registers `/cost`: live OpenRouter rates for
the pinned models, in dollars per million tokens.

```
OpenRouter rates ($/Mtok), live from openrouter.ai

  deepseek/deepseek-v4-flash-0731  $0.07 in / $0.18 out / $0.02 cache read
  deepseek/deepseek-v4-pro-0813    $0.58 in / $1.74 out / $0.02 cache read
  deepseek/deepseek-v4.1-flash     $0.15 in / $0.60 out / $0.003 cache read
    peak windows up to $0.30 in / $1.20 out
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
  four hours stale like Pi's cached catalog. On fetch failure it falls back to
  the catalog metadata Pi's cost accounting uses and says so in the header.
- **Per-token to per-Mtok conversion** is done here; OpenRouter prices in
  per-token strings. Zero components are omitted; cache write precedes cache
  read when charged. Models with usage-window pricing (V4.1 Flash's
  weekday/weekend and 100k/400k tiers) show the off-peak rates in the row and
  name the peak rates on an indented line, because the row alone would
  understate the price of a long session.
- **No model calls** — the command is free to run. Like the built-in `/model`, it is
  interactive-only: print mode (`pi -p`) sends leading-slash prompts to the model
  instead of executing them, and `ctx.ui.notify` has no print-mode surface.

`rates.ts` is pure and unit-tested in `tests/cost-command.test.ts`.