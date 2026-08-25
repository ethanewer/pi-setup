# Trace dataset export and sanitation

## Purpose

`bin/convert-pi-traces` builds the private `eewer/pi-trace-cache` Hugging Face dataset from local Pi sessions and selected monitor-bench traces. It produces derived training data. It never edits raw session JSONL or session archives.

The exporter handles the `pi-ai 0.84.3` reasoning-details incident described in [`incidents/PI-AI-0.84.3-REASONING-DETAILS.md`](incidents/PI-AI-0.84.3-REASONING-DETAILS.md). This document defines the filter contract and the procedure for future dataset updates.

## Contamination boundary

A response with severe token-fragment reasoning is not valid training data. Every later turn in that trajectory is also excluded because the model generated it from contaminated context.

The exporter applies this rule at the first affected assistant message:

- Keep messages before the affected assistant message if the prefix contains an earlier assistant response.
- Drop the affected assistant message and the complete suffix.
- Drop the whole row if there is no earlier clean assistant response.
- Do not alter reasoning text by joining or deleting newlines.

A final answer or tool call after the boundary remains contaminated even if its formatting looks normal. The model saw malformed history before producing it.

## Detector

Converted cache rows do not retain `thinkingSignature` or structured `reasoning_details`. The production filter therefore uses assistant `reasoning_content`. A block is severe only when all conditions hold:

- At least 3 newline characters
- Newline-to-character ratio of at least `0.04`
- At least 2 suspicious adjacent line boundaries

A boundary is suspicious when both lines contain text, neither side is a list or heading marker, the left side does not end at common prose or code punctuation, and at least one side is 15 characters or shorter.

The implementation is `newline_reasoning_metrics()` in `bin/convert-pi-traces`. Tests include token-fragment output that must be rejected and paragraphs, lists, and code that must remain byte-identical.

This is a conservative detector, not a general prose-quality score. It can miss mild splitting. One-word poetry or unusual hand-formatted text can resemble the defect. Review every new manifest entry before upload.

## Raw-session evidence

Raw Pi JSONL provides a stronger structural indicator. Parse each assistant thinking block's `thinkingSignature` as JSON. Consecutive objects of either form indicate the `0.84.3` storage regression:

```json
{"type":"reasoning.text","text":"first fragment"}
{"type":"reasoning.text","text":" second fragment"}
```

or:

```json
{"type":"reasoning.summary","summary":"first fragment"}
{"type":"reasoning.summary","summary":" second fragment"}
```

Encrypted details between text details break adjacency and must remain opaque. Do not infer corruption merely because a signature contains several different detail types.

The converted-row detector remains required even when raw JSONL exists. The signature proves that replay structure was malformed, while severe output text identifies the training-data boundary. If future source formats retain structured reasoning details, record the structural finding in the manifest and cut no later than the first assistant response generated after malformed replay.

## Sanitation metadata

A retained clean prefix carries this marker in `source_metadata.newline_reasoning_sanitization`:

```json
{
  "policy": "pi-ai-0.84.3-newline-reasoning-v1",
  "action": "truncate_before_first_affected_assistant",
  "reason": "severe_token_fragment_reasoning",
  "first_affected_message_index": 8,
  "first_affected_assistant_ordinal": 4,
  "original_message_count": 33,
  "retained_message_count": 8,
  "dropped_message_count": 25,
  "metrics": {
    "characters": 4351,
    "newlines": 560,
    "newline_character_ratio": 0.128706,
    "suspicious_boundaries": 400,
    "severe": true
  }
}
```

The numbers above show the schema. The manifest contains the actual measured values.

Truncation invalidates conversation-level accounting collected from the original suffix. The exporter sets token totals to zero, sets `api_usage_complete` to false, changes `token_accounting` to `unavailable_after_newline_reasoning_truncation`, and clears suffix exception fields. It sets `segment_reason` to `newline_reasoning_clean_prefix`.

## Exclusion manifest

Every run writes a timestamped local manifest:

```text
~/pi-trace-cache-tool/out/pi-trace-sanitization-<timestamp>.jsonl
```

Uploads replace the stable private dataset path:

```text
manifests/newline-reasoning-v1.jsonl
```

Each record contains:

- `policy`
- `trace_key`
- `source_path`
- `action`
- `reason`
- First affected message index and assistant ordinal
- Original, retained, and dropped message counts
- Detector metrics

`action` is either `truncate_before_first_affected_assistant` or `exclude_trace`. Records are sorted by trace key for stable diffs. Rows that already carry the current marker are re-emitted in later manifests, so the stable manifest describes the current dataset rather than only the newest local scan.

Do not reuse this policy ID after changing thresholds, boundary semantics, or metadata fields. Add a new policy ID, a new manifest path, migration tests, and a dataset-card update. Old markers must remain interpretable.

## Export procedure

Install dependencies in an isolated environment and run a dry export first:

```bash
cd ~/pi-setup
uv run --with zstandard --with huggingface_hub \
  bin/convert-pi-traces --dry-run --out /tmp/pi-trace-review
```

Review:

1. The summary counts for truncated and excluded rows.
2. Every line in `pi-trace-sanitization-*.jsonl`.
3. The retained message immediately before each cut.
4. The first dropped reasoning block and its detector metrics.
5. Several unflagged multiline reasoning blocks from each model family.
6. The generated JSONL for secrets and malformed message boundaries.

Run the upload only after that review:

```bash
uv run --with zstandard --with huggingface_hub bin/convert-pi-traces
```

The uploader downloads all existing remote shards, merges by `trace_key`, and applies the sanitation filter to the full union. This second pass is required. It removes affected suffixes from rows uploaded by older pipeline versions or another machine. The uploader then writes one replacement union shard, uploads the stable manifest and dataset card, and deletes superseded shards.

`--keep-newline-reasoning` is for local forensic exports. The command rejects it unless `--no-upload` or `--dry-run` is also present.

## Post-upload verification

Download the new remote shard and verify these conditions before treating it as SFT input:

- Exactly one union shard exists under `data/`.
- The old union shard no longer exists.
- Every manifest trace key maps to either one marked clean-prefix row or an excluded trace.
- Every marked row ends before its recorded first affected message.
- No assistant `reasoning_content` block passes `newline_reasoning_metrics(...)["severe"]`.
- No token totals or suffix exceptions survive on truncated rows.
- The stable manifest and dataset card exist.

The 2026-08-25 cleanup produced a 101-row union. Eight rows were reduced to clean prefixes, none required full exclusion, and a full-shard scan found no remaining severe blocks. Treat these counts as historical verification, not fixed expectations for later exports.

## Future incidents

Do not add model or provider allowlists for this defect. Any trace produced by an unpatched or regressed adapter must be scanned. The confirmed incident crossed Kimi, Qwen, GLM, and several OpenRouter routes.

When a similar serialization bug appears:

1. Add a versioned detector and manifest schema.
2. Seed tests with confirmed bad output and similar valid output.
3. Define the contamination boundary before changing data.
4. Keep raw inputs immutable.
5. Apply the policy to local rows and the downloaded remote union.
6. Review all decisions before upload.
7. Verify the uploaded shard independently.
8. Document the producer-side fix in `docs/incidents/` and link it here.

Never synthesize a repair for hidden reasoning. If the original trajectory after a boundary cannot be trusted, retain a clean prefix or exclude it.
