# pi-model-prices

`/models` — the built-in `/model` picker, plus API prices.

Pi's built-in `/model` selector shows `id [provider]` and offers no extension hook
into its rendering, so this package registers a sibling command with the same
interaction model and the pricing the built-in one omits:

```
→ z-ai/glm-5.3 [openrouter, $1.40 in, $4.40 out, $0.26 cache read] ✓
  gpt-5.6-luna [openai, $0.20 in, $1.20 out, $0.25 cache write, $0.02 cache read]
  gpt-5.6-sol [openai, $5 in, $30 out, $6.25 cache write, $0.50 cache read]
```

- Rates are dollars per million tokens, read from the model catalog — the same
  `model.cost` metadata Pi's cost accounting uses (including the OpenRouter
  catalog refresh), not a hand-maintained price list.
- Zero components are omitted; cache write is listed before cache read when a
  model charges for it.
- A model reached through a subscription login (Claude Pro/Max, ChatGPT,
  Grok, …) shows `[provider, sub]` — the same condition Pi's own footer uses
  (`isUsingOAuth` and the provider's OAuth flow marked `isSubscription`).
- A model with input-based pricing tiers gets a footer line under the selected
  row, e.g. `long-context rates above 272k input tokens (whole request): …`,
  because the row's rates are the short-context ones.
- Keys match the built-in selector: type to fuzzy-filter, up/down to move
  (wrapping), Enter to switch, Esc/Ctrl+C to cancel, Tab to toggle the
  scoped/all scope. The current model is sorted first and marked `✓`.
- `/models <provider/model>` (or a bare unique model id) switches directly, the
  way the built-in command's argument form does. `/models` in a non-TUI mode
  prints the priced list instead of opening a picker.

Switching uses `pi.setModel`, so it changes the session's model (and notifies on
a missing API key) but does not rewrite the saved default the way picking from
the built-in `/model` does; re-run the built-in selector when a default should
stick.

First-party package: no upstream, nothing to re-vendor. Pricing-label logic
lives in `extensions/model-prices/pricing.ts` and is unit-tested from
`tests/model-prices.test.ts`.
