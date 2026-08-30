# Garnet Mesa — cultivar ledger sweep

The **Garnet Mesa** research greenhouse keeps its irrigation/shading rules for
each cultivar scattered across three legacy fixtures that use three different
serializations. You must build a reusable program that decodes all of them and
merges them with the cultivar roster into one structured allocation report.

## Environment

- Working directory: `/app`. The read-only input tree `/app/data` already
  contains the fixtures described below. Python 3.12 is available as
  `python3`. Standard library only; no network needed.
- **Do not modify anything under `/app/data`.**

## Deliverables (both required)

1. `/app/allocate.py` — a runnable Python program:
   ```
   python3 /app/allocate.py <input_dir> <output_json>
   ```
   It reads the fixture tree rooted at `<input_dir>` and writes the JSON
   allocation report to `<output_json>`. It must work on **any** fixture tree
   conforming to the contract (the verifier re-runs it on fresh hidden trees).

2. `/app/allocation.json` — the report produced by running your program on the
   shipped fixtures:
   ```
   python3 /app/allocate.py /app/data /app/allocation.json
   ```

## Input tree layout

```
<input_dir>/
  roster.tsv
  ledger/
    stores.pkl      (optional — may be missing)
    trellis.b64     (optional — may be missing)
    almanac.txt     (optional — may be missing)
```

### `roster.tsv`

Tab-separated, one header row then one row per cultivar, columns in order:

```
cultivar_id  plot  family  sown
```

`cultivar_id` is a non-empty token (strip surrounding whitespace from every
field). Blank lines are skipped. A data row that does not have exactly 4
tab-separated fields is skipped.

### `ledger/` — constraint fixtures in three encodings

Every fixture maps a `cultivar_id` to a **constraint object**
`{"water": "<string>", "shade": "<string>"}`:

- `stores.pkl` — a Python **pickle** of a dict `{cultivar_id: constraint}`.
- `trellis.b64` — a **base64** blob (possibly wrapped over several lines;
  ignore line breaks and whitespace) that decodes to UTF-8 JSON holding the
  same dict shape.
- `almanac.txt` — plain text, one constraint per line:
  `cultivar_id|water|shade` (strip whitespace around each of the three
  fields). Blank lines are ignored. If the same id appears on several lines,
  the **first** occurrence wins. A line that does not split into exactly three
  `|`-separated fields is ignored.

**Merge rule (priority order):** `stores.pkl` > `trellis.b64` >
`almanac.txt`. Each roster cultivar gets its constraint from the
highest-priority source that provides a usable one. A fixture entry is usable
only when the id maps to a JSON-like object with both a string `water` and a
string `shade` (an entry missing a key, or whose value is not an object, is
unusable and the merge falls through to the next source). Ids in the fixtures
that are not in the roster are ignored.

**Resilience rule:** any ledger file that is missing, unreadable, corrupt (bad
base64), or whose decoded payload is not a JSON-like object is skipped
entirely — the program must never crash on it; whatever the remaining sources
provide is used, and the rest is `none`.

## Output report (JSON)

```json
{
  "allocations": [
    {"cultivar_id": "VG-101", "plot": "N1", "family": "Solanaceae",
     "sown": "2033-03-04", "water": "300ml", "shade": "40%",
     "source": "stores.pkl"}
  ],
  "sources_used": ["almanac.txt", "stores.pkl"],
  "unassigned": ["VG-105"]
}
```

- `allocations`: one object per roster row, **in roster order**. When no
  source supplies a usable constraint, `water` and `shade` are the literal
  string `"none"` and `source` is `"none"`.
- `sources_used`: sorted list of the distinct source files (one of
  `stores.pkl`, `trellis.b64`, `almanac.txt`) that supplied at least one
  roster constraint. Empty list when none did.
- `unassigned`: roster ids (in roster order) with no usable constraint.

## Edge cases the verifier probes

- all three fixtures present with **overlapping ids** (priority decides);
- a **corrupt base64** blob and a blob decoding to a non-object (both skipped);
- a pickle containing non-object entries and entries missing a key (fall
  through);
- duplicate / malformed / blank lines in `almanac.txt`;
- ids present in fixtures but absent from the roster (ignored);
- a roster id with no constraint anywhere (`none` / listed in `unassigned`);
- a missing ledger file; an empty (header-only) roster.

## Constraints

- Standard library only; deterministic; no hard-coding of the shipped fixture
  values — the verifier runs your program unchanged on fresh hidden trees.
- Do not read from `/tests`; do not modify `/app/data`.
