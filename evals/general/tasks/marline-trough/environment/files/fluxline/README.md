# fluxline

A telemetry normalization pipeline for the marlow observability stack
(Node.js 22). `fluxline` reads a large NDJSON dump of sensor records, applies
a per-sensor normalization config, and writes the normalized NDJSON records
to an output file. It is built to run on huge dumps (hundreds of thousands to
millions of records) on modest hosts, so streaming and a bounded working set
are first-class requirements, not afterthoughts.

```
node lib/pipeline.js <input.ndjson> <config.json> <output.ndjson>
```

Exit codes: `0` success, `1` runtime error, `2` usage or config error.

## Module map

| module | responsibility |
|---|---|
| `lib/pipeline.js` | entrypoint; wires the input stream, the transform stage, and the output stream |
| `lib/transform.js` | the normalization stage: one async `enrich(rec, cfg)` per record, driven by `transform(lines, cfg)` |
| `lib/config.js` | loads and strictly validates the config JSON |
| `scripts/gen_fixture.mjs` | deterministic NDJSON workload generator (seeded) for local work |
| `test/` | the project test suite (`node --test`) |

## Input format

One JSON object per line (NDJSON). Blank lines are skipped. Lines that do not
parse as JSON are skipped. Every other line must be an object with these
**recognized** fields:

| field | type | notes |
|---|---|---|
| `ts` | int | epoch seconds |
| `sensor` | string | which metric stream |
| `raw` | int | the observed value (may be negative) |
| `site` | string | which site emitted the row |
| `unit` | string | optional, ignored by the transform |

Unknown fields are ignored. `raw` and `ts` are integers in every record the
pipeline accepts; the pipeline never emits floats.

## Config format

```json
{
  "scales": { "cpu": 10, "mem": 1, "net": 1000 },
  "drops": [
    { "sensor": "cpu", "below": 5000 },
    { "sensor": "net", "above": 3000000 }
  ],
  "emit": ["site", "ts", "sensor", "value"]
}
```

- `scales` (required): map from sensor name to an **integer** multiplier.
- `drops` (optional, default `[]`): list of rules
  `{ "sensor": <string>, "below"?: <int>, "above"?: <int> }`; at least one of
  `below`/`above` must be present. `below`/`above` apply to the normalized
  value, and a rule only applies to rows whose `sensor` equals the rule's
  `sensor`.
- `emit` (required): the ordered list of keys for the output record. `"value"`
  is special and is filled with the normalized value; every other key must be
  present in the input row or the row is dropped.

Invalid configs make the pipeline exit with code 2.

## Transformation semantics (exact)

For each input row object `rec`, in input order:

1. `scale = scales[rec.sensor]`. If the sensor is not a key of `scales`, drop
   the row (unknown sensor).
2. `value = rec.raw * scale` (integer arithmetic).
3. For every drop rule `r` with `r.sensor == rec.sensor`:
   - if `r` has `below` and `value < r.below`, drop the row;
   - if `r` has `above` and `value > r.above`, drop the row.
   A row is dropped as soon as any rule drops it.
4. Build the output object: for each key `k` in `emit`, in order:
   - `k == "value"` → the output value is the normalized `value`;
   - otherwise the output value is `rec[k]`, and if `rec` does not contain
     `k`, drop the row.
5. Otherwise, emit `{"k": rec[k] ... , "value": value}` with keys in exactly
   the `emit` order.

The output file contains one compact JSON object per emitted row (`\n`
separated), in input order. Rows that are dropped never appear. Records that
survive are emitted **bit-for-bit equal** for identical inputs and configs; the
pipeline is deterministic.

## Working-set budget (hard requirement)

`fluxline` must process arbitrarily large dumps with **bounded memory**. The
operational ceiling is:

> Peak RSS must stay below **192 MiB** while streaming any workload.
> The input must be consumed as a stream (`node:fs` `createReadStream`
> piped into `node:readline` `createInterface`), never read wholesale into
> memory, and the output must be written incrementally.

The CI memory probe (a downstream consumer of this repo) reruns the pipeline
on multi-hundred-thousand-row inputs, samples `VmHWM` from
`/proc/<pid>/status`, and fails any run whose high-water mark breaches the
192 MiB ceiling. It also inspects `lib/pipeline.js` and `lib/transform.js`
and fails if the input is loaded with `readFile`/`readFileSync` or if a
line-batching `toArray` helper is used in place of streaming.

## Workload generation

```
node scripts/gen_fixture.mjs <seed> <rows> <output.ndjson> [sensor_set]
```

`sensor_set` is one of `standard` (default), `plant`, or `grid`. The output
is fully deterministic for a given `(seed, rows, sensor_set)` and includes a
small share of blank lines, malformed lines, unknown-sensor rows, and rows
missing the `site` field, so the tolerant paths are exercised.

## Tests

```
node --test
```

The suite exercises the transformation semantics on small inline fixtures;
it is not a substitute for the working-set budget above (small data does not
stress memory).