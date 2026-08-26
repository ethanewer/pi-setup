# `pi-ai 0.84.3` reasoning-details regression

## Status

The repository contains protections for new streams, historical sessions, and derived training data.

| Area | Protection |
|---|---|
| New provider streams | The version-specific patch concatenates adjacent reasoning text and summary deltas. |
| Historical Pi sessions | The patch normalizes adjacent stored deltas before replay. It does not rewrite session JSONL. |
| Installed package (bun/library path) | `install.sh`, `bin/verify-pi-ai-reasoning-fix`, and `bin/pi-setup-doctor` check the fix. |
| Installed package (npm bundle path) | `bin/patch-pi-bundle` patches `dist/bundle/chunks/openai-completions-*.js`, the code the npm entrypoint actually loads; `install.sh` runs it and `bin/pi-setup-doctor` checks it. |
| Hugging Face trace cache | `bin/convert-pi-traces` removes affected suffixes and writes a decision manifest. |
| Regression tests | `tests/reasoning-details-patch.test.ts` and `tests/trace-sanitization.test.ts` cover replay and export behavior. |

The affected published version is `@earendil-works/pi-ai 0.84.3`. Upstream fixed new stream storage after that release:

- Commit: [`c5ad7c1b0f7623bbfdf64dd4967fa6e99c15c01a`](https://github.com/earendil-works/pi/commit/c5ad7c1b0f7623bbfdf64dd4967fa6e99c15c01a)
- Pull request: [earendil-works/pi#8605](https://github.com/earendil-works/pi/pull/8605)
- Pull request title: `fix(ai): concatenate openai completions reasoning deltas`

The upstream commit fixes new streamed deltas. This repository also normalizes old stored signatures during replay. Do not remove the repository patch until a published Pi release has both behaviors, or an equivalent compatibility path keeps historical sessions safe.

## Symptom

Affected assistant reasoning contains newlines between words or token fragments:

```text
smartctl
 not
 installed
```

Longer examples split words such as `sb\natch` and `L\ning`. This differs from valid Markdown, code, paragraph breaks, and numbered plans.

The malformed newlines are present in the provider response stream, final assistant thinking block, stored session JSONL, and `thinkingSignature`. The ordinary Pi TUI renderer displays the text but does not create it.

## Root cause

OpenRouter streams `reasoning_details` as deltas. `pi-ai 0.84.3` preserved each delta as a separate object in the assistant thinking signature. A normal logical reasoning item could be stored as:

```json
[
  {"type":"reasoning.text","text":"Let","format":"unknown","index":0},
  {"type":"reasoning.text","text":" me read the file","format":"unknown","index":0}
]
```

On the next same-model turn, Pi replayed that array as complete reasoning details. OpenRouter requires consecutive details of the same text or summary type to be concatenated. The correct text detail is:

```json
[
  {"type":"reasoning.text","text":"Let me read the file","format":"unknown","index":0}
]
```

Pi did not insert newline characters into the old reasoning text. It introduced object boundaries at token-like stream boundaries. The provider or routed model then reacted to that malformed replay structure and emitted new reasoning with real token-fragment newlines. Pi stored those newlines. Later turns could receive both fragmented detail arrays and already-malformed text.

The failure chain was:

1. OpenRouter streamed text or summary reasoning deltas.
2. `pi-ai 0.84.3` stored adjacent deltas as separate complete-looking objects.
3. Pi replayed the fragmented array on a later turn.
4. The provider or model interpreted the artificial boundaries.
5. The model emitted token-fragment newlines.
6. Later responses used contaminated conversation context.

## Scope

The problem is not specific to one model or routed provider. Historical failures occurred with Kimi, Qwen, and GLM models through OpenRouter. Routed providers included Alibaba, DigitalOcean, Modal, and Moonshot AI.

The Linux installation first encountered the bug while the top-level coding-agent package was still `0.84.2`. That package allowed `pi-ai ^0.84.2`, so Bun resolved the newly published `pi-ai 0.84.3`. A later Mac installation had a coherent `0.84.3` package set and still failed. Package-version drift was not required, but caret-ranged transitive dependencies allowed the regression to arrive before the top-level version changed.

The following were tested and were not required causes:

- Pi's TUI renderer
- The monitor extension or a monitor invocation
- Built-in tool definitions
- The monitor and setup skill wording
- A previously malformed assistant response
- One routed OpenRouter provider

Prompt and routing changes can change how often a stochastic failure appears. They do not explain the stored fragmented arrays.

## Evidence

### Timeline

| Event | UTC |
|---|---|
| `pi-ai 0.84.3` published | 2026-08-24 11:06:27 |
| Linux global packages installed | 2026-08-24 20:05:20 |
| First severe Linux anomaly | 2026-08-24 21:14:43 |
| Coherent Mac `0.84.3` installation starts | 2026-08-24 23:18:25 |
| Upstream merges the stream-concatenation fix | 2026-08-25 09:19:31 |
| Severe Mac Qwen sessions | 2026-08-25 17:00 and 17:11 |

### Controlled replay

Three clean Kimi prefixes were replayed four times under each condition:

| Prior reasoning form | Severe runs | Newlines / thinking characters |
|---|---:|---:|
| Fragmented details stored by `0.84.3` | 4/12 | 141 / 1,736 |
| Adjacent details merged | 0/12 | 2 / 1,552 |
| Signatures removed | 0/12 | 0 / 1,500 |

The two newlines in the normalized condition formed an ordinary paragraph break. Merging changed the object structure but left the reasoning text unchanged. Routing metadata was stable within each prefix condition.

### Historical traces

An initial converted cache contained 91 traces and 2,495 assistant reasoning blocks. A conservative text detector found 31 severe blocks. All 31 were in two post-update Mac Qwen sessions. Additional Linux sessions contained the same signature structure and output pattern, including one GLM session.

The first investigation counted any newline and therefore mixed valid Qwen plans with token splitting. The corrected analysis uses fragment boundaries, newline density, and manual review. [`docs/TRACE-DATASET.md`](../TRACE-DATASET.md) records the production filter and its limits.

### Reproduction rules

Future tests should preserve real message order, tool-call IDs, tool results, thinking signatures, model metadata, and provider metadata. Capture the outgoing HTTP payload as well as the returned stream. Run comparison requests serially and record OpenRouter generation metadata so routing and load do not weaken the result.

Do not feed signatures produced by a newer adapter into an older adapter and call the result a version comparison. The `0.84.2` adapter interpreted `0.84.3` signature JSON as an arbitrary assistant-message property, which was not a valid historical replay. Compare sessions generated by each version or change only the identified detail normalization.

The exact historical system prompt was not stored in session JSONL. Tests reconstructed it with Pi's prompt builder. This limits claims about the original prompt, but it does not affect the captured fragmented signatures, the upstream code defect, or the normalized-versus-fragmented replay result.

## Repository fix

[`patches/pi-ai@0.84.3-reasoning-details.patch`](../../patches/pi-ai@0.84.3-reasoning-details.patch) adds two protections:

1. Stream handling appends adjacent `reasoning.text` and `reasoning.summary` deltas to one logical detail.
2. Signature parsing applies the same normalization before replaying historical arrays.

Opaque `reasoning.encrypted` entries remain separate and preserve order. The normalizer carries forward common fields such as `id`, `format`, `index`, and text signatures.

`install.sh` applies the patch only to the pinned Pi version. Installation then runs `bin/verify-pi-ai-reasoning-fix` against a local OpenAI-compatible server. The verifier checks the outgoing historical replay payload and the signature generated from a new streamed response. `bin/pi-setup-doctor` reports a missing installed fix.

### Bundle entrypoint gap (found 2026-08-26)

The library patch above does not cover pi's npm entrypoint. `pi-coding-agent`'s
`bin` is `dist/bundle/cli.js`, which loads pi-ai from
`dist/bundle/chunks/openai-completions-*.js` — a bundled copy — instead of
`node_modules/@earendil-works/pi-ai`. Any pi installed through npm (every
harbor benchmark container, runs 1–3 and the first run-4 attempt) therefore
ran the unpatched code even when the node_modules copy carried the fix.
`bin/verify-pi-ai-reasoning-fix` did not catch this because it imports the
library file directly. The host `pi` wrapper was unaffected: it runs
`dist/bun/cli.js`, which resolves pi-ai from the hoisted, patched
`node_modules` copy.

[`bin/patch-pi-bundle`](../../bin/patch-pi-bundle) applies the same two
behaviors to the bundle chunk by exact, version-guarded (0.84.3), idempotent
string replacement. `install.sh` runs it after the library patch, and
`bin/pi-setup-doctor` reports the bundle state separately. Benchmark base
images (`evals/general/benchmark/bases/`) bake pinned pi 0.84.3 with both
fixes, and `PAgent.install()` verifies the bundle fix before every rollout,
refusing to run on unpatched code. Runtime proof: the same golden-example
trial stored its first-turn signature as five fragmented deltas before the
bundle fix and as one merged entry after it; run-4 (522 transcripts, 1,745
signatures) showed zero fragmented signatures.

## Upgrade checklist

Use this checklist whenever the Pi pin changes:

1. Read the new `pi-ai` OpenAI-completions stream and replay code.
2. Confirm that adjacent streamed text details are concatenated.
3. Confirm that adjacent streamed summary details are concatenated.
4. Confirm that historical fragmented signatures are normalized before replay.
5. Confirm that encrypted or unknown detail types remain opaque and ordered.
6. Run `tests/reasoning-details-patch.test.ts` and `bin/verify-pi-ai-reasoning-fix` against the candidate installation.
7. Confirm `bin/patch-pi-bundle` applies cleanly to the new bundle chunk, or re-target it; re-check `bin/pi-setup-doctor`'s bundle line.
8. Run `bin/convert-pi-traces --dry-run` and inspect every new sanitation decision.
9. Remove or rebase the version-specific patches only after all checks pass.
10. Update this incident document, `vendor.json`, and the installer in the same commit.

A release note or the presence of upstream commit `c5ad7c1b` proves only the new-stream half of the fix. Historical replay normalization needs a separate check.

## Response procedure

If token-fragment reasoning returns:

1. Stop resuming the affected session. A stored malformed signature can trigger later turns.
2. Preserve the raw JSONL without editing it.
3. Capture the installed coding-agent and `pi-ai` versions.
4. Run `bin/verify-pi-ai-reasoning-fix` and `bin/pi-setup-doctor`.
5. Inspect `thinkingSignature` arrays for adjacent `reasoning.text` or adjacent `reasoning.summary` objects.
6. Test a clean multi-turn session through the same provider path.
7. Fix stream storage and historical replay before collecting more traces.
8. Run the trace exporter. Review its manifest before updating Hugging Face.
9. Never repair training data by deleting or joining output newlines. Keep a clean prefix or exclude the row.

Raw sessions are provenance. Derived exports are the only files the sanitation pipeline may change.
