# Review of the newline-reasoning report

## Verdict

The original report got several important points right:

- Pi's TUI does not insert the newlines.
- The response already contains the newlines when `pi-ai` receives it.
- The monitor extension, tool schemas, and skill wording are not required.
- Replaying prior reasoning is central to the failure.

Its final conclusion is too cautious and misses the specific bug. The evidence now points to a regression in `pi-ai 0.84.3` with high confidence.

`pi-ai 0.84.3` stores every streamed OpenRouter `reasoning_details` delta as a separate `reasoning.text` object. It then replays that array as if each delta were a complete reasoning detail. OpenRouter expects adjacent text and summary deltas to be concatenated before replay.

The broken stored shape looks like this:

```json
[
  {"type":"reasoning.text","text":"Let","format":"unknown","index":0},
  {"type":"reasoning.text","text":" me read the STATE.md file ...","format":"unknown","index":0}
]
```

A longer turn can contain hundreds of token-like fragments as separate objects. This is the same granularity later seen in malformed output such as `L\ning`, `sb\natch`, and newlines between short words.

Upstream merged the direct fix one day after `0.84.3` was published:

- Commit: `c5ad7c1b0f7623bbfdf64dd4967fa6e99c15c01a`
- PR: <https://github.com/earendil-works/pi/pull/8605>
- Title: `fix(ai): concatenate openai completions reasoning deltas`

The PR states: "As per OpenRouter, we should be concatenating reasoning deltas when consecutive ones are of the same type." Its before example matches the fragmented signatures in the affected Pi sessions. The fix is on upstream `main` but is not in the published `0.84.3` package.

## Timeline

The timing matches the regression closely.

| Event | UTC time |
|---|---|
| `pi-ai 0.84.3` published | 2026-08-24 11:06:27 |
| Linux global Pi packages installed | 2026-08-24 20:05:20 |
| First severe Linux anomaly in the benchmark session | 2026-08-24 21:14:43 |
| Mac Pi update session installs and verifies all packages at `0.84.3` | starts 2026-08-24 23:18:25 |
| Severe Qwen traces on the Mac | 2026-08-25 17:00 and 17:11 |
| Upstream merges the delta-concatenation fix | 2026-08-25 09:19:31 |

The Linux install still had `pi-coding-agent 0.84.2`, but that package declares `@earendil-works/pi-ai: ^0.84.2`. Bun therefore resolved the newly published `pi-ai 0.84.3`. This explains why the bug appeared before the repository changed its top-level Pi pin to `0.84.3`.

The mixed Linux package versions are not needed to trigger the bug. The Mac update trace shows a coherent `0.84.3` installation, and later Mac Qwen sessions have the same word-splitting failure.

## Evidence from `eewer/pi-trace-cache`

The private dataset currently has 91 converted traces and 2,495 assistant reasoning blocks. It does not preserve reasoning signatures, but it preserves reasoning text and source metadata.

A conservative split-text heuristic was used. It requires at least three newlines, a newline-to-character ratio of at least 4 percent, and at least two boundaries involving short non-list fragments.

Results:

| Trace group | Reasoning blocks | Severe split-text blocks |
|---|---:|---:|
| All rows except the two post-update Mac Qwen traces | 2,417 | 0 |
| Post-update Mac Qwen traces, dataset rows 83 and 84 | 78 | 31 |

All 31 severe blocks occur in these two files:

```text
/Users/ethanewer/.pi/agent/sessions/--Users-ethanewer-posttraining-2606--/
2026-08-25T17-00-31-070Z_01a039dd-c7de-7be7-a72e-612fdce6817a.jsonl

/Users/ethanewer/.pi/agent/sessions/--Users-ethanewer-posttraining-2606--/
2026-08-25T17-11-54-731Z_01a039e8-366b-75f0-b8fd-dcf36be0a025.jsonl
```

Examples include:

```text
The
 last socket
 s
.rh
m
Y
```

and a 4,351-character reasoning block with 560 newlines:

```text
Wait —
 the
 NV
TE environment variable is exported
 inside
 the sb
atch script
```

This is not normal Qwen planning. The original report's distinction between severe Kimi splitting and mostly normal Qwen multiline reasoning is wrong. Qwen shows the same token-fragment failure at large scale.

The archive also supplies a useful machine-level comparison. The Mac update session records an installation that verifies `pi-coding-agent`, `pi-ai`, and `pi-tui` at `0.84.3`. The process running that update had loaded the old code at startup and remained clean. Fresh, substantial sessions after the update show the failure.

A live Linux session on 2026-08-25 also reproduced the same pattern with `z-ai/glm-5.3`. Its first turns were clean. After fragmented reasoning details had been replayed, a response changed to one newline between nearly every short fragment. The bug is therefore not limited to Kimi and Qwen.

## Provider routing

OpenRouter generation metadata was fetched for 286 historical Kimi and Qwen responses. The failure is not tied to one routed provider.

The first severe responses used:

- Kimi benchmark: DigitalOcean
- Kimi SMART: Alibaba
- Kimi FPS: Moonshot AI
- Qwen: Alibaba

The longer benchmark session also produced split responses through DigitalOcean, Modal, Moonshot AI, and Alibaba. The FPS session produced several clean Moonshot AI responses followed by a split Moonshot AI response. The SMART session produced a clean Alibaba response followed by split Alibaba responses.

Provider changes can affect which stochastic response occurs, but one provider route does not explain the bug.

## Replay experiments

The strongest original experiment remains useful. With a minimal system prompt and no tool definitions:

- Fragmented prior reasoning signatures produced severe Kimi splitting in 6 of 9 runs.
- Removing prior reasoning signatures produced no Kimi newline activity in 9 runs.

This result now has a concrete explanation. Removing the signatures removes the malformed array of unmerged streaming deltas.

A follow-up experiment tested the upstream fix more directly. It replayed the same three Kimi prefixes serially under three conditions, four times each:

| Prior reasoning form | Severe split runs | Newlines / thinking characters |
|---|---:|---:|
| Fragmented `reasoning_details` from `0.84.3` | 4/12 | 141 / 1,736 |
| Adjacent text and summary deltas merged as in `c5ad7c1b` | 0/12 | 2 / 1,552 |
| Signatures removed | 0/12 | 0 / 1,500 |

The two newlines in the normalized condition were an ordinary paragraph break, not word splitting. Payload capture confirmed that normalization changed prior assistant turns from arrays such as 2 and 8 detail objects to one logical detail object each. It left the reasoning text unchanged.

OpenRouter generation metadata also removed a routing confound. Every benchmark-prefix request in all three conditions used Alibaba. Every SMART-prefix request used Modal. Every FPS-prefix request used Modal.

This serial A/B test is stronger than the original old-adapter comparison. It changes the malformed structure identified by the upstream fix without deleting the prior reasoning text.

The monitor and skill experiments still support the narrower conclusion that prompt wording changes probabilities but is not causal. Their aggregate newline counts are not a good failure metric because they mix normal lists and paragraphs with word splitting.

## Mistakes in the original report

### It missed the upstream fix

The report stopped at "possible replay bug." Upstream had already merged a fix named for the exact malformed structure. The `0.84.3` package predates that fix.

### It understated the Qwen failure

The trace cache contains 31 severe Qwen blocks in 78 reasoning blocks from two post-update sessions. Local sessions also contain many severe Qwen blocks. Qwen is not merely producing normal numbered plans.

### It treated the mixed installation as an unexplained amplifier

The mixed Linux state has a direct cause. `pi-coding-agent 0.84.2` permits `pi-ai 0.84.3` through its caret dependency. That transitive resolution introduced the faulty replay code before the top-level Pi pin changed. A fully aligned `0.84.3` install still has the bug, as the Mac traces show.

### The old-adapter comparison was not a valid historical replay

The experiment fed `0.84.3`-generated signature arrays into `pi-ai 0.84.2`. The old adapter treated the entire JSON signature string as an arbitrary assistant-message property name. Its captured payload confirms this. A real `0.84.2` session would not have generated those signature arrays in the first place.

The old adapter happened to produce clean responses in three trials, but that does not isolate adapter version cleanly.

### Several experiments launched repetitions concurrently

The multi-prefix scripts use `Promise.all`, so many requests ran at once. This weakens small frequency comparisons because routing, load, and cache timing were uncontrolled. It does not invalidate the signature-removal result, the historical timeline, or the upstream code finding.

### It counted any newline as activity

Normal paragraph and list formatting was grouped with word splitting. This especially distorted the Qwen comparisons. A split-fragment metric or manual classification is needed.

## Corrected cause

The likely chain is:

1. OpenRouter streams `reasoning_details` as text deltas.
2. `pi-ai 0.84.3` stores each delta as a separate complete-looking object.
3. On the next same-model turn, Pi replays the fragmented array.
4. OpenRouter or the routed model interprets the object boundaries as reasoning-segment boundaries.
5. The model begins emitting newlines at token-like boundaries.
6. Pi faithfully stores and displays that malformed provider output.

This explains all central observations:

- The first response in a fresh session is usually clean.
- Failure begins after at least one reasoning turn is replayed.
- Removing signatures stops the Kimi reproduction.
- Multiple models and routed providers can show it.
- Prompt and tool changes alter frequency but are not required.
- The first observed failures closely follow installation of `pi-ai 0.84.3`.

## Impact on model inputs and outputs

The defect changed model behavior, not only Pi's display. The severe newlines were already present in the provider response that Pi stored and rendered. Pi did not add them while drawing the TUI.

There is no evidence that Pi inserted newline characters into otherwise unchanged prior reasoning text before sending it back. The replay payload kept the original text but split it across many `reasoning_details` objects at token-like boundaries. Those artificial object boundaries came from Pi's stream handling and were not boundaries the model had authored as complete reasoning segments. The provider or routed model then reacted to that malformed structure by producing new output with token-like newlines. In the controlled replay test, merging adjacent objects left the prior reasoning text unchanged and reduced severe split output from 4 of 12 runs to 0 of 12.

After a model had emitted a malformed response, its actual newline characters were stored and could be replayed on later turns. Those later newlines were model-generated, even though the Pi-created fragmentation was the trigger.

## Remediation

Updating only the top-level package to make every installed package `0.84.3` will not fix this. Published `0.84.3` contains the regression.

Safe options are:

1. Wait for a release that contains upstream commit `c5ad7c1b` and then update through the repository installer.
2. Temporarily patch `pi-ai 0.84.3` with the upstream delta-concatenation change and verify it against clean multi-turn sessions.
3. Pin a coherent pre-regression `0.84.2` installation, including transitive packages, until the fixed release is available.

After installing a fixed version, start a new session. Existing affected sessions contain fragmented signature arrays. Upstream commit `c5ad7c1b` fixes how new responses are stored, but it does not normalize old arrays during replay. Resuming an old session may therefore preserve the trigger. A complete compatibility fix should also merge adjacent `reasoning.text` and `reasoning.summary` entries when replaying old signatures.

## Remediation status

The setup now keeps Pi on the latest published release, `0.84.3`, and applies a version-specific `pi-ai` patch during installation. The patch contains upstream commit `c5ad7c1b`'s stream concatenation and normalizes adjacent text and summary entries whenever Pi parses a stored reasoning signature. The replay change makes existing affected sessions safe to resume without rewriting their JSONL files.

`bin/verify-pi-ai-reasoning-fix` runs a local OpenAI-compatible test server. It verifies the installed package's outgoing replay payload and the reasoning signature created from new streamed deltas. `install.sh` runs this check after applying the patch, and `bin/pi-setup-doctor` checks that the installed code still contains both paths.

Global packages were changed only through `install.sh` after the investigation. The installed `pi-coding-agent` and `pi-ai` versions are now both `0.84.3`.

## SFT data status

`bin/convert-pi-traces` now applies the same conservative severe-split detector during every export and again after merging existing Hugging Face rows. It truncates an affected conversation immediately before the first malformed assistant turn, discards that turn and its suffix, and excludes the row if no earlier clean assistant response exists. It does not rewrite raw traces or attempt to join newlines. Truncated rows invalidate stale token and exception accounting and carry deterministic policy metadata.

The current `eewer/pi-trace-cache` shard has 101 rows. Eight rows were reduced to clean prefixes, the uploaded manifest at `manifests/newline-reasoning-v1.jsonl` records those decisions, and validation found no remaining severe split-reasoning blocks.
