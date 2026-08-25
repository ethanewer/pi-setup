# Report: newline-heavy reasoning in Pi sessions

## Executive summary

Some Pi sessions show assistant reasoning with newlines inserted between words or short token fragments. Examples include:

```text
smartctl
 not
 installed
```

and:

```text
Fresh
-install defaults
```

The problem is not caused by the ordinary Pi TUI renderer. The malformed text appears in the provider response stream, in the persisted session JSONL, and in the reasoning signature.

The experiments found a likely Pi-side contributor:

> Pi's `pi-ai` reasoning replay path, especially the structured `reasoning_details` format used by `pi-ai 0.84.3`, changes the payload sent to OpenRouter.

That path can affect both Kimi and Qwen because both sessions use the same OpenRouter OpenAI-compatible adapter. Kimi shows the more severe word-splitting behavior. Qwen often produces ordinary multiline planning, so its newline activity is not always the same failure mode.

The monitor extension and `update-pi-setup` skill text did not show a consistent causal effect. Built-in tools were not required. A mixed global installation remains a concern:

```text
pi-coding-agent: 0.84.2
pi-ai:           0.84.3
pi-tui:          0.84.3
```

The repository installer currently specifies `pi-coding-agent 0.84.3`, so the installed global tree is out of alignment. This should be treated as a possible amplifier, although it has not been proven to be the original historical trigger.

## The problem being investigated

The historical symptom was a transition from clean assistant reasoning to reasoning with excessive newlines. The important feature is that the previous conversation was often clean immediately before the first bad response.

The investigation considered these possible causes:

- Pi's TUI renderer
- A Pi extension
- The monitor tool
- A skill description or skill file
- Tool-call replay
- Replayed reasoning signatures
- A malformed earlier assistant response
- `pi-ai` package behavior
- OpenRouter or the underlying model

The experiments preserved real conversation history rather than reducing the setup to a single synthetic user message.

## Historical prefixes

Several prefixes were extracted from real Pi session JSONL files. Each prefix ended immediately before the first historically contaminated assistant response.

### Kimi benchmark prefix

Source:

```text
/home/eewer/.pi/agent/sessions/--home-eewer-pi-setup-evals-general--/
2026-08-24T21-13-13-022Z_01a0359e-c63e-7c2d-9fd2-7443999bfcda.jsonl
```

The historical first anomaly was at JSONL line 15.

Before that response:

- 5 message entries
- 2 prior assistant thinking blocks
- Prior thinking contained 0 newlines
- The prefix included a user request, an assistant `read` tool call, a read result, an assistant `bash` tool call, and a bash result

The historical first anomalous response contained approximately 130 characters and 9 newlines. A later response in the same session contained approximately 1,186 characters and 268 newlines.

### Kimi SMART prefix

Source:

```text
/home/eewer/.pi/agent/sessions/--home-eewer-pi-setup-evals-general--/
2026-08-24T23-05-46-632Z_01a03605-d387-7b60-bb82-cf525863883c.jsonl
```

The historical first anomaly was at line 12.

Before that response:

- 8 message entries
- Prior thinking blocks contained 0 newlines
- The prefix included multiple bash calls and results

The historical bad response contained approximately 178 characters and 27 newlines.

### Kimi FPS trainer prefix

Source:

```text
/home/eewer/.pi/agent/sessions/--home-eewer-fps-aim-trainer--/
2026-08-24T21-11-16-099Z_01a0359c-fd83-7ed9-a802-387640bb4257.jsonl
```

The historical first anomaly was at line 49.

Before that response:

- 45 message entries
- 7 prior thinking blocks
- Every prior thinking block contained 0 newlines
- The prefix included many real bash and read calls and their results

The historical bad response contained approximately 209 characters and 36 newlines.

### Qwen fresh-session prefix

Source:

```text
/home/eewer/.pi/agent/sessions/--home-eewer-pi-setup--/
2026-08-25T06-59-01-952Z_01a037b7-1ac0-7627-bc9b-6197ed934111.jsonl
```

The historical first newline-heavy response was at line 7.

Before that response:

- 3 message entries
- 1 prior assistant thinking block
- The prior thinking contained one normal trailing newline
- The prefix included a real `read` tool call and result

The Qwen response was newline-heavy, but its formatting was mostly a normal numbered plan rather than the severe Kimi-style word splitting.

## Method

The prefixes were passed to `pi-ai` using the same message objects from the session files. This preserved:

- User messages
- Assistant messages
- Assistant thinking blocks
- Thinking signatures
- Tool calls
- Tool-call IDs
- Tool results
- Original model and provider metadata

The harness recorded:

- Thinking character count
- Number of newline characters
- Newline-to-character ratio
- Whether the output contained thinking
- Whether it contained text or tool calls
- A preview of the raw thinking text
- The outgoing payload shape in the focused experiments

The historical system prompt was not stored in the session JSONL, so the system prompt had to be reconstructed with Pi's `buildSystemPrompt`. This is an important limitation. The A/B comparisons used the same reconstructed prompt within each experiment, but they cannot prove that the reconstruction is byte-identical to the historical prompt.

## Experiment 1: provider output versus TUI rendering

The anomalous newlines were found in:

1. Provider reasoning deltas received by `pi-ai`
2. The final assistant thinking block
3. The persisted Pi session JSONL
4. The stored `thinkingSignature`

This means the text is already malformed before normal TUI rendering.

The ordinary assistant renderer was compared between coding-agent `0.84.2` and `0.84.3`. The renderer files were byte-identical. No renderer code splits words or inserts newlines at word boundaries.

The TUI may display the text, but it is not the source of the malformed content.

## Experiment 2: replaying clean real prefixes

The exact Kimi benchmark prefix was replayed with current `pi-ai 0.84.3`. The prefix was clean immediately before the new request.

The three initial runs produced:

| Run | Thinking characters | Newlines | Ratio |
|---|---:|---:|---:|
| 1 | 63 | 6 | 9.5% |
| 2 | 0 | 0 | No thinking |
| 3 | 122 | 5 | 4.1% |

The first run contained text such as:

```text
jobs
/ and
 specs/ seem
 empty or
 don't
 exist?
```

This reproduces the important historical transition: clean context followed by malformed reasoning. A malformed previous reasoning block is therefore not required.

## Experiment 3: multiple clean prefixes

A larger experiment used four real prefixes, three repetitions each, with:

- Current `pi-ai 0.84.3`
- Current monitor tool and schema
- Current monitor skill catalog
- Current `update-pi-setup` skill catalog
- The reconstructed Pi system prompt
- The original real conversation prefix

The results were:

| Prefix | Runs with newline activity | Newlines / thinking characters |
|---|---:|---:|
| Kimi benchmark | 1/3 | 19 / 358 |
| Kimi SMART | 1/3 | 24 / 176 |
| Kimi FPS | 3/3 | 141 / 1,203 |
| Qwen fresh | 2/3 | 94 / 10,141 |

Across all 12 runs:

- 7/12 contained at least one newline
- 278 newlines
- 11,878 thinking characters
- Aggregate ratio: 2.34%

For Kimi alone:

- 5/9 runs contained newline activity
- 184 newlines
- 1,737 thinking characters
- Aggregate ratio: 10.6%

The Kimi FPS prefix was the most repeatable. It produced word-split reasoning in all three current-text runs.

This rules out a single malformed historical response as the only trigger. Different clean prefixes can enter the same failure pattern.

## Experiment 4: removing tool definitions

The exact Kimi benchmark prefix was tested with current `pi-ai` after removing tool definitions. The historical tool calls and results remained in the prefix, but no tool definitions were supplied for the new request.

Earlier results were:

| Context | Runs with newline activity | Newlines / thinking characters |
|---|---:|---:|
| Four coding tools, no skills | 2/5 | 6 / 539 |
| No tools and no tool list | 3/5 | 13 / 716 |

The no-tool condition still produced newline reasoning. It sometimes produced more activity than the condition with tools.

Therefore the current coding tool schemas are not required to trigger the issue.

## Experiment 5: skill catalogs and skill files

Skill catalogs were tested against the exact Kimi benchmark prefix.

An initial comparison found:

| Context | Runs with newline activity | Newlines / thinking characters |
|---|---:|---:|
| Tools, no skills | 2/5 | 6 / 539 |
| Current skill catalog | 4/5 | 105 / 973 |

This suggests that adding skill metadata can affect output frequency or severity. However, the sample was small, and adding skills changes the full system prompt rather than one isolated token.

Individual current skill tests produced:

| Skill | Runs with newline activity | Newlines / thinking characters |
|---|---:|---:|
| `unslop` | 1/3 | 15 / 420 |
| `monitor` | 2/3 | 11 / 352 |
| `update-pi-setup` | 1/3 | 39 / 389 |

These results are inconsistent. No individual skill was required.

The full skill files were also appended as simulated `read` tool results after a clean benchmark prefix:

- Current monitor skill: 6 newlines / 55 thinking characters
- Old monitor skill: 0 newlines / 143 thinking characters
- Current setup skill: 0 newlines
- Old setup skill: no thinking output

Those were single-run tests and occurred after an added skill-reading turn, so they do not prove that the file contents cause the historical first anomaly.

## Experiment 6: current and old monitor/setup text

The repository contains older versions of the monitor extension and skills.

The older monitor snapshot was taken from commit:

```text
3f10ffb
```

The older `update-pi-setup` skill snapshot was taken from:

```text
67697b9
```

The old monitor code differs in several ways:

- Older wording such as `NON-BLOCKING`
- Different parameter descriptions
- No current `heartbeatMinutes` parameter
- Different prompt guideline wording
- Different tool result wording
- Different `monitor_status` and `monitor_kill` descriptions

The setup skill changes are mostly editorial wording changes. They do not introduce a new operating instruction with an obvious relationship to newline placement.

The same four real prefixes were tested with current `pi-ai 0.84.3`, but with the older monitor tool/schema and older monitor and setup skill catalogs.

| Prefix | Current text | Older monitor/setup text |
|---|---:|---:|
| Kimi benchmark | 1/3, 19 / 358 | 0/3, 0 / 473 |
| Kimi SMART | 1/3, 24 / 176 | 2/3, 83 / 802 |
| Kimi FPS | 3/3, 141 / 1,203 | 0/3, no thinking in all runs |
| Qwen fresh | 2/3, 94 / 10,141 | 3/3, 68 / 4,567 |

Aggregate results:

- Current text: 7/12 runs, 2.34% newline ratio
- Older text: 5/12 runs, 2.58% newline ratio

The Kimi-only counts were 5/9 versus 2/9, but this comparison is weakened by the old-text FPS runs producing no thinking at all. The old text still produced split reasoning for SMART and more newline activity for Qwen.

The results do not show a consistent direction. The monitor and setup-skill wording may change model behavior in individual requests, but they do not explain the first anomaly as a deterministic cause.

The monitor `/watch` slash-command prompt was not treated as part of every request. It is only relevant when invoked. A monitor custom message also appears later than the earliest historical Kimi anomaly.

## Experiment 7: `pi-ai` version comparison

The strongest software-level difference is between `pi-ai 0.84.2` and `0.84.3`.

### Current adapter

The current adapter accepts and preserves OpenAI-style reasoning details, including:

- `reasoning.text`
- `reasoning.summary`
- `reasoning.encrypted`

When prior thinking signatures are replayed, `pi-ai 0.84.3` sends them as structured `reasoning_details`.

In a captured exact benchmark-prefix payload:

- The first prior assistant message contained 2 reasoning-detail objects
- The second prior assistant message contained 8 reasoning-detail objects
- Both prior assistant messages also contained their original tool calls
- The reasoning-detail order was preserved

### Old adapter

The old adapter handled reasoning details differently. It primarily handled encrypted reasoning associated with tool calls. The captured old payload contained an unusual serialized reasoning-fragment property resembling:

```json
[
  {"type":"reasoning.text","text":"Let", "...":"..."},
  {"type":"reasoning.text","text":" me read the STATE.md file ...", "...":"..."}
]
```

It did not send the same structured `reasoning_details` array as the current adapter.

### Exact-prefix comparison

The exact five-message Kimi benchmark prefix was tested three times with each adapter.

Current `pi-ai 0.84.3`:

```text
63 chars, 6 newlines
0 chars, 0 newlines
122 chars, 5 newlines
```

Old `pi-ai 0.84.2`:

```text
174 chars, 0 newlines
152 chars, 0 newlines
0 chars, 0 newlines
```

This supports the hypothesis that the new replay path may increase susceptibility to the Kimi pattern. It is not conclusive because the provider is stochastic and the two adapters send different payloads.

In the larger multi-prefix test, the old adapter still produced newline reasoning for Qwen, so adapter version does not fully explain every newline.

## Experiment 8: minimal system prompt and signature controls

A further experiment removed Pi-specific prompt content.

The test used:

```text
You are a helpful assistant.
```

It supplied:

- No skills
- No tool definitions
- The original real prefix, including prior tool calls and results
- Either preserved or removed prior reasoning signatures

The current `pi-ai 0.84.3` results with prior signatures preserved were:

| Prefix | Runs with newline activity | Newlines / thinking characters |
|---|---:|---:|
| Kimi benchmark | 3/3 | 10 / 326 |
| Kimi SMART | 2/3 | 81 / 606 |
| Kimi FPS | 1/3 | 50 / 424 |
| Qwen fresh | 3/3 | 135 / 9,831 |

Kimi total:

- 6/9 runs
- 141 newlines / 1,356 thinking characters
- 10.4% aggregate ratio

With prior signatures removed:

| Prefix | Runs with newline activity | Newlines / thinking characters |
|---|---:|---:|
| Kimi benchmark | 0/3 | 0 / 476 |
| Kimi SMART | 0/3 | 0 / 302 |
| Kimi FPS | 0/3 | 0 / 174 |
| Qwen fresh | 3/3 | 121 / 13,799 |

Kimi produced no newline activity in 9 runs when the prior thinking signatures were removed.

This is not a pure signature-only experiment. Removing the signatures also prevents the prior thinking from being sent in the same structured replay form. The result means that replayed prior reasoning, including its serialization format, is important to the Kimi behavior. It does not yet identify whether the problem is in Pi's serialization, OpenRouter's handling of the serialized data, or the model's response to that data.

For Qwen, removing signatures did not remove newline activity. Its output was mostly normal multiline planning in both conditions.

## Why both Kimi and Qwen can show the problem

Kimi and Qwen share this request path:

```text
Pi
  -> pi-ai openai-completions adapter
  -> OpenRouter chat/completions
  -> reasoning-capable model
```

Both models can receive:

- The same general system prompt
- The same tool history
- The same reasoning replay structure
- The same OpenRouter reasoning configuration
- The same package implementation

This gives two explanations for seeing newline activity with both models.

### Shared payload handling

The current adapter changes the outgoing history by replaying prior thinking as `reasoning_details`. OpenRouter interprets that structure before sending the request to the model.

If that format affects how the model continues its reasoning, the same software path can affect multiple models. The models may respond differently. Kimi may turn the effect into severe word-level splitting, while Qwen may turn it into long, normally formatted numbered plans.

### Model-specific formatting

Qwen naturally produces more visibly structured reasoning. In the fresh Qwen historical prefix, the output looked like a normal plan:

```text
Current status:
- 524 tasks ...
- run-1 ...
- Remaining tasks:
  1. Fix ...
```

That is newline-heavy, but not necessarily corrupted.

Kimi's output is more diagnostic because it places newlines inside short phrases and between word fragments.

The fact that both models produce newlines does not prove that they have the same underlying failure. The shared adapter and OpenRouter path may be common contributors, while each model expresses the result differently.

## The current installation drift

The repository installer contains:

```bash
PI_VERSION="0.84.3"
```

The actual global installation is:

```text
@earendil-works/pi-coding-agent 0.84.2
@earendil-works/pi-ai             0.84.3
@earendil-works/pi-tui            0.84.3
```

The global package metadata also pins:

```json
"@earendil-works/pi-coding-agent": "0.84.2"
```

while the lockfile resolves related packages, including `pi-ai`, to `0.84.3`.

This is a real installation inconsistency. It means the current Pi process is not running one coherent package version set.

The mismatch matters because:

- `pi-ai` controls provider payload construction and response parsing.
- `pi-coding-agent` controls session behavior, system-prompt construction, and tool integration.
- `pi-tui` controls display behavior, although the renderer was not responsible for this problem.

The package drift is not proof of historical causality. The repository commit introducing coding-agent `0.84.3` came after the earliest historical Kimi anomaly. That specific coding-agent upgrade cannot explain the first occurrence. The `pi-ai` replay behavior remains a possible contributor, especially for later or repeated occurrences.

## What the experiments rule out

### The TUI inserts the newlines

Unlikely. The malformed text exists in provider deltas and persisted session content.

### A malformed earlier response is required

False. Several clean real prefixes reproduced newline reasoning in the next response.

### Built-in tool definitions are required

False. The behavior survived removal of tool definitions.

### A monitor invocation is required

False. The earliest anomaly occurs before any monitor custom message or monitor call.

### The current monitor skill text is required

False. Older monitor text still produced the behavior in some prefixes, and current text did not produce it reliably in others.

### The `update-pi-setup` skill is required

False. Removing the skill and using older text did not eliminate the behavior.

## What remains uncertain

The following questions are not settled:

1. Whether `pi-ai 0.84.3` itself has a replay bug.
2. Whether the structured payload is valid but causes OpenRouter or the model to continue badly.
3. Whether OpenRouter introduces or normalizes the newline placement.
4. Whether provider routing changed between requests.
5. Whether the exact historical system prompt contained another relevant extension or instruction.
6. Whether the mixed installed package versions amplify the effect.
7. Whether temperature, reasoning budget, cache state, or provider routing settings affect the frequency.

The historical JSONL does not include the exact outgoing HTTP payload or the exact system prompt, so the original request cannot be reconstructed perfectly.

## Overall conclusion

The problem is a provider-visible reasoning formatting failure. Pi displays text that is already malformed in the response it receives.

The best current explanation is:

1. Pi replays prior assistant reasoning through the `pi-ai` OpenAI/OpenRouter adapter.
2. `pi-ai 0.84.3` sends that reasoning using structured `reasoning_details`.
3. OpenRouter and the model receive a different continuation context than they received under the older adapter.
4. Kimi sometimes responds with word-split reasoning.
5. Qwen often responds with normal multiline reasoning, but can still show newline-heavy output.

The monitor extension and skill wording are not supported as the primary cause. They may affect probabilities because they change prompt content, but they did not produce a repeatable current-versus-old effect.

The most important unresolved Pi-side issue is the mixed package installation. A fully aligned, temporary installer-managed installation should be tested against the same prefixes before changing the global installation. A direct OpenRouter request using a captured Pi payload would also separate provider behavior from Pi response parsing.

No global installation changes were made during these experiments. This report is the only repository file added for the investigation.
