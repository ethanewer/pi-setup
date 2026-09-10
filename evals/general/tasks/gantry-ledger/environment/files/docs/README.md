# gantry-ledger: extraction eval project

A regression-evaluation setup for a structured-extraction prompt family. The
project ships:

- `data/records.jsonl` — 200 shipment records (the reference set). Each line:
  `{"id", "text", "gold"}`. `gold` holds the ground-truth fields
  `ref` (uppercase alphanumeric air-waybill number), `date` (ISO-8601),
  `amount` (two-decimal number), `carrier` (carrier name, or the literal
  `UNKNOWN` when the shipment has no determinable carrier).
- `prompts/v1.txt`, `prompts/v2.txt` — two shipped prompt versions.
- `model/` — a deterministic simulated extractor ("the model"). Local, pure
  function, no network. Interface: `model.extract(prompt_text, record_text)`
  returns a dict with keys `date`, `amount`, `ref`, `carrier`. The module
  also exposes the constant `model.UNKNOWN`.

## Metrics

Both metrics are computed per record set and are deterministic — the model
and the records are fixed, so any correctly implemented harness reports
identical numbers on identical inputs.

- **ref_acc** (primary) — fraction of records whose extracted `ref` equals
  the gold `ref`.
- **fabrication_rate** (secondary, lower is better) — fraction of records
  whose extracted carrier is a concrete value (anything other than the
  literal `UNKNOWN`) and differs from the gold carrier. Emitting `UNKNOWN`
  for a carrier the text does not determine is not a fabrication; emitting a
  made-up concrete carrier is.

## The model card (read this before writing prompts)

The model is a simulated instruction-following extractor. Its behaviour
changes with the prompt:

1. **Canonical normalization** — when the prompt requests canonical output
   forms (ISO-8601 dates, uppercase separator-free alphanumeric refs,
   two-decimal amounts), extracted values are normalized, which repairs
   cosmetic record defects (lowercased refs, stray separators). Prompts that
   do not request it pass values through untouched, and cosmetic defects
   leak into the output.
2. **Carrier completion vs abstention** — when a record has no `Carrier`
   line, only a `Fwd code`, the model's behaviour follows the prompt:
   - with no completion guidance the model abstains and emits the literal
     `UNKNOWN`;
   - with completion guidance (wording such as "complete the carrier",
     "guess", "infer", "best judgment", or an appended reference table) the
     model fills the carrier from the table (exact code match) or, failing
     that, from the closest code by edit distance — including cases where
     that guess is wrong.
3. **Revision behaviour (override)** — if a prompt contains BOTH completion
   guidance and abstention markers (e.g. `UNKNOWN`, "do not guess",
   "uncertain", "not stated"), the LATER of the two wins for the carrier
   field. This is deliberate and consistent: the extractor treats the most
   recent explicit carrier instruction as authoritative.

The model never consults anything except its two arguments, and it never
invents carrier values unless the prompt's completion guidance is in force.

## Documented baseline

Measured on the reference set (and stable across comparable fresh sets):

| prompt | ref_rate | fabrication_rate |
|---|---|---|
| `prompts/v1.txt` | 0.60 | 0.00 |
| `prompts/v2.txt` | 0.97 | 0.19 |

`v2` fixes the primary metric but trades in a fabrication regression: a
moved-up `ref_rate` alongside a moved-down fabrication story. The eval
harness you build must reproduce this trade-off from its own measurements,
and any newer prompt version must improve BOTH metrics against the bar set
in the task brief rather than trading one for the other.