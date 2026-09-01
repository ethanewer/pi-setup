# Repartition a row-major tensor record

You are given a tensor record expressed as a JSON object with a row-major
`values` array and a `shape` (list of non-negative integer dimensions). Your
job is to write one self-contained Python CLI tool that can (a) split the
values into exactly **three contiguous, as-even-as-possible shards** along with
a manifest, and (b) rebuild and verify the original tensor from those shards.

## Deliverable

Write a single executable Python program at **`/app/reshard.py`**. It must be a
reusable tool that works on ANY input following the documented contract, not
just the supplied file. You run it yourself to produce the visible outputs.

Do **not** modify any of the input files shipped under `/app` (in particular
`/app/tensor.json` is read-only input data). Do not read `/tests` or `/solution`.

## Provided files under `/app`

- `/app/tensor.json` — the supplied visible input. **Read-only; do not modify it.**

## Tool contract

`/app/reshard.py` exposes two subcommands on the CLI:

```
python3 /app/reshard.py shard --input <tensor.json> --outdir <dir>
python3 /app/reshard.py join  --manifest <manifest.json> --outdir <dir>
```

### `shard`

Reads the tensor JSON and splits its row-major `values` into exactly three
contiguous shards that are as evenly sized as possible. It writes four files
into `<dir>` (creating the directory if needed):

- `shard-0.json`, `shard-1.json`, `shard-2.json`, and `manifest.json`.

Each shard file is:

```json
{"shard_index": <i>, "offset": <int>, "count": <int>, "values": [...]}
```

where `values` is the exact slice of the original `values` array belonging to
this shard (values are copied verbatim, order and full value preserved).

The **even-split rule** for `element_count = N` (product of `shape`):

- `base = N // 3`, `rem = N % 3`
- shard `i` (0,1,2) has `count = base + (1 if i < rem else 0)` and
  `offset = sum of the counts of shards before it`.

Shards may be empty when `rem` cannot fill three non-empty shards (e.g. `N < 3`
yields counts `1,1,0`, and `N == 0` yields three empty shards). The three shard
slices always tile `values` exactly in order: `shard-i.values` equals
`values[shards[i].offset : shards[i].offset + shards[i].count]` and the union
reproduces `values` in full.

The `manifest.json` is:

```json
{
  "shape": [<int>, ...],
  "element_count": <N>,
  "num_shards": 3,
  "checksum": "<64 lowercase hex>",
  "shards": [
    {"index": 0, "offset": <int>, "count": <int>},
    {"index": 1, "offset": <int>, "count": <int>},
    {"index": 2, "offset": <int>, "count": <int>}
  ]
}
```

- `element_count` = product of all `shape` dimensions.
- `checksum` = the lowercase hex SHA-256 digest of the compact JSON serialization
  of the values array: `hashlib.sha256(json.dumps(values, separators=(",", ":")).encode()).hexdigest()`.
- `shards` lists exactly three entries in index order 0,1,2 with their
  offset/count.

On success the tool exits `0` and prints a one-line summary to stdout. On any
invalid input it prints a clear message to stderr and exits **non-zero** (do
yourself the favor of failing loudly rather than producing a wrong shard).

### `join`

1. Read the manifest at `<manifest.json>` plus the three `shard-<i>.json` files
   in the same `<dir>` (the manifest path and the shards live in one directory).
2. Reconstruct the original `values` array from the shards in offset order, and
   verify: the manifest declares exactly 3 shards; each shard's `count` matches
   the manifest; the shards are contiguous and tile `[0, element_count)` exactly;
   `len(reassembled) == element_count`; the `shape` element_count equals the
   manifest `element_count`; and `checksum(reassembled values) == manifest.checksum`.
   The checksum is defined exactly as above.
3. On success write `<dir>/reconstructed.json`:

```json
{"shape": [...], "values": [...]}
```

and exit `0`. On any mismatch or missing/inconsistent file, print an error to
stderr and exit non-zero (you reconstructed nothing wrong).

## Input format

The tensor JSON is an object:

```json
{"shape": [<int>, ...], "values": [<int>, ...]}
```

- `shape` is a non-empty list of non-negative integers (any number of
  dimensions). Zero and one-dimensional shapes are valid.
- `values` is a list of any integers (including negatives and repeats) whose
  length must equal the product of `shape`. An empty values list is valid.
- Any deviation from this (missing key, wrong type, negative dimension,
  value count mismatch, non-integer value) is **malformed** and must be rejected.

## Output format summary

The four shard outputs and the `<outdir>/manifest.json`; the `join`
output `<outdir>/reconstructed.json`. All must be valid JSON with the exact
keys/order shown above.

## Commands you are expected to run

```
python3 /app/reshard.py shard --input /app/tensor.json --outdir /app
python3 /app/reshard.py join --manifest /app/manifest.json --outdir /app
```

## Expected visible result

For `/app/tensor.json` a correct shard produces shard sizes
`4, 4, 4`, offsets `0, 4, 8` and `reconstructed.json` equal to the original
tensor. Sanity-check `manifest.json` has `"num_shards": 3`.

## Edge cases hidden verifier will probe

The verifier reruns `/app/reshard.py` on fresh inputs under `/tests/hidden`,
and also checks error handling. Make your tool handle all of these:

- **Non-divisible** counts (`N` not a multiple of 3 → counts differ by 1 and the
  larger counts come first).
- **Multi-dimensional shapes** (e.g. `[1,1,4]`) and count that matches their
  product.
- **Negative and arbitrary integer values** that must be preserved exactly.
- **`N < 3`** (counts like `1,1,0`) and **`N == 0`** (three empty shards,
  checksum is the digest of the compact `[]`).
- **Malformed inputs** must always be rejected with a non-zero exit: shape/value
  count mismatch, negative dimension, missing key, or non-integer values.

The join mode must be verified too: hidden verifier reassembles hidden tensors
and requires `reconstructed.json` to equal the original input byte-for-byte.

## Machine notes

Single container; network is unavailable during verification. Work offline.
Python 3.12 is available; the `hashlib` and `json` modules are part of the
standard library. There is no GUI, no root wrapper, no interactive session.