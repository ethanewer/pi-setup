# Merge the fragmented snapshot roster

The **Tarn Quay** supply cooperative keeps its item roster in a directory of
snapshot exports written by three different shop terminals. Each terminal has
its own export format, several items appear in more than one snapshot, and the
formats disagree about types (ids and values sometimes arrive as zero-padded
strings, names sometimes carry stray padding whitespace).

You must write a **single Python program** `/app/merge.py` that reads every
snapshot in a snapshots directory, normalizes the rows, resolves duplicate
ids, and exports the merged roster as a JSON array sorted by id.

The grader runs your program on the shipped snapshots **and on fresh hidden
snapshots** (see CLI below), so it **must be written generally**, not
hard-coded to the shipped files.

## The snapshots directory

A snapshots directory (e.g. `/app/snapshots`) contains flat files whose names
end in `.csv`, `.jsonl`, or `.json`. All three formats carry the same three
fields per record:

| field | meaning |
|-------|---------|
| `id`    | the item's primary key (an integer; some terminals emit it zero-padded as text, e.g. `"001"`) |
| `name`  | the item name (a string; may carry leading/trailing whitespace padding) |
| `value` | an integer stock value (some terminals emit it zero-padded as text, e.g. `"007"`; negatives are allowed) |

Formats:

- **`.csv`** — comma-separated with a header line `id,name,value`. Names may be
  double-quoted and may contain commas or doubled quotes (`""`) inside the
  quotes (standard CSV quoting).
- **`.jsonl`** — one JSON object per line, e.g.
  `{"id": 7, "name": "harbor tin", "value": "300"}`. Blank lines are ignored.
- **`.json`** — a JSON file holding an **array of record objects**.

## Normalization

For every record, regardless of source format:

1. `id` → cast to **int** (strip whitespace first; `"001"` → `1`).
2. `name` → a string with leading/trailing whitespace **stripped** (internal
   spacing/case is kept exactly as-is — do **not** lowercase or otherwise
   rewrite it).
3. `value` → cast to **int** (strip whitespace first; `"007"` → `7`,
   `"-5"` → `-5`).

A record that cannot be normalized (a missing `id`/`name`/`value` key, or an
`id`/`value` that is not an integer after stripping, or a malformed JSON
line/object) is **skipped entirely**. Files with any other extension are
ignored.

## Duplicate resolution

The same `id` may appear several times, across and within files, with
different `name`/`value`. Keep **exactly one record per id**: the one that is
smallest by `(value, name)` — compare `value` as an integer first; on a value
tie compare `name` as a plain string. (After normalization, any two records
that tie on `(value, name)` are identical, so the result is always
deterministic.)

## Deliverables (both required)

1. `/app/merge.py` — the merge program, with this interface:
   ```
   python3 /app/merge.py <snapshots_dir> <output_json>
   ```
   It reads every snapshot in `<snapshots_dir>` and writes the merged roster
   to `<output_json>`. It must work on any snapshots directory conforming to
   the contract above.

2. `/app/merged.json` — the JSON roster your program produces **when run on
   the shipped `/app/snapshots` directory**:
   ```
   python3 /app/merge.py /app/snapshots /app/merged.json
   ```

## Required output format

`<output_json>` is a single valid **JSON array** of objects, one per merged
record, **sorted ascending by `id`**, with **no duplicate ids**, each object
containing exactly the three fields:

```json
[{"id": 1, "name": "Foxtrot Lamp", "value": 7}, ...]
```

- `id`: integer; `name`: string (padding stripped, otherwise verbatim);
  `value`: integer.
- Complete: one element per surviving record — nothing mergeable is dropped.
- An empty snapshots directory yields the empty array `[]`.

Ordering, duplicate ids, element count, and field types are each checked by
distinct grader asserts.

## Constraints

- The verifier runs your program **unchanged** (`python3 /app/merge.py`) on
  hidden snapshots directories, so do not hard-code file names or contents.
- Use only the Python 3 standard library (`csv`, `json`, `os`, ...).
- Do not modify the files under `/app/snapshots`.

## What the hidden cases probe

- a snapshots directory with **no files** → `[]`;
- heavy **duplicate ids** across files with value ties resolved by the
  smaller `name`, **negative** values, zero-padded ids and values;
- CSV with **quoted names containing commas/quotes**, plus **malformed**
  rows (bad JSON lines, records missing a field, non-integer ids/values)
  that must be skipped;
- sources whose file order is the **reverse** of the required id order
  (the output must still be sorted ascending by id, e.g. starting at `0`).
