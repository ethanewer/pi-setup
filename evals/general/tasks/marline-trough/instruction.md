# marline-trough: restore bounded-memory streaming in the fluxline pipeline

`/app/fluxline` is a Node.js telemetry normalization pipeline owned by the
marlow observability team. It reads a large NDJSON dump of sensor records,
applies a per-sensor normalization config, and writes the normalized NDJSON
records to an output file. **Read `/app/fluxline/README.md` first**; it is
the contract: exact input format, config schema (`scales` / `drops` /
`emit`), the record-by-record transformation semantics, the command line,
and the working-set budget. Nothing below overrides it.

## The deliverable

The pipeline entrypoint is `/app/fluxline/lib/pipeline.js`. It must remain
callable exactly as documented:

```
node /app/fluxline/lib/pipeline.js <input.ndjson> <config.json> <output.ndjson>
```

and must apply the documented transformation semantics exactly (identical
rows, in input order, JSON-value identical per line) for any valid input and
config. You may edit any file under `/app/fluxline` to make that true; do
not touch anything else under `/app`.

## Environment

- Node 22.23 (`node` on PATH), `git`, `python3`, `gzip` are installed.
- `/app/fluxline` is a git repository with history, a module layout
  (`lib/`, `scripts/`, `test/`, `data/`), and a test suite that is green in
  the shipped state. `scripts/gen_fixture.mjs` is a deterministic NDJSON
  workload generator.
- No network access. Everything needed is on disk.

## Why you were called in

The pipeline's small-data test suite passes and the semantics are correct,
but the deployed build does not meet the README's working-set budget on real
workloads: feed it a large dump and its peak memory climbs far beyond the
documented ceiling as the input grows, instead of staying flat. The throughput
looks fine and the output is correct. The problem only shows up at scale.
The team shipped this state and asked for a repair, preserving the documented
behavior.

Reproduce it:

```
cd /app/fluxline
node scripts/gen_fixture.mjs 7 600000 /tmp/flux.ndjson
node lib/pipeline.js /tmp/flux.ndjson data/sample.config.json /tmp/out.ndjson
```

Monitor peak resident set while that runs (sample `VmHWM` from
`/proc/<pid>/status` for the node process, or watch `ps` output — peak RSS
is what matters). Use larger row counts (800k, 1.2M, 2M) to see the trend
clearly: a correct pipeline holds a flat ~90-110 MiB at any size, the
shipped build does not. `gen_fixture.mjs` honours
`<seed> <rows> <output.ndjson> [sensor_set]` and is deterministic per seed.

## Acceptance criteria (the verifier enforces exactly these)

1. **Correctness.** For every input the pipeline emits exactly the rows the
   README's rules describe: dropped rows absent, surviving rows in input
   order with identical field values and exactly the `emit` keys. The
   verifier recomputes the expected output independently and compares
   JSON-value by JSON-value per line. Exit code must be `0`.
2. **Streaming.** The input must be consumed as a stream using Node's
   `createReadStream` / `createInterface` APIs and written incrementally via
   `createWriteStream`. The verifier statically inspects `lib/pipeline.js`
   and `lib/transform.js` and fails on `readFile`, `readFileSync`, or
   `toArray`. Reading the whole file into memory is not an acceptable
   repair, with or without a size check.
3. **Bounded memory.** The verifier runs the pipeline on large hidden NDJSON
   inputs (hundreds of thousands of records each) and reads the process's
   peak RSS from `/proc/<pid>/status` `VmHWM` (sampled during the run and
   read one final time after it exits), rejecting any run whose high-water
   mark exceeds the README's declared ceiling of **192 MiB** (196608 KiB). A
   correct repair holds flat near ~90 MiB at any input size.

You will not know the hidden inputs; they are generated at verification time
from the same documented contract (different sensors, scales, drop rules,
`emit` lists, field values, and sizes). Your fix must generalize, not
special-case the shipped sample.

## Working pointers

- The unit suite covers semantics, not scale. Read `test/pipeline.test.js`
  and the README before you start; nothing about the correct behavior is
  hidden from you.
- `git log` will tell you how this codebase was built and what the recent
  changes were, which may save you profiling time.
- Do not change the CLI contract, the config schema, or the documented
  transformation rules. If you break them, criterion 1 fails.
- Test at scale before you declare done: your fix must hold its RSS on
  800k+ row workloads, not just on the sample.

## Deliverables

- `/app/fluxline/lib/pipeline.js`, the entrypoint, repaired in place, with
  any other files under `/app/fluxline` you need to fix, such that all three
  acceptance criteria hold from a fresh container.