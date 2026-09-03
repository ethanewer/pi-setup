# mini-runner harness (v1)

A deliberately small test-runner scaffold used as the base for the
`ds-runner-shard` extension task. Everything here is self-authored for this
bench; nothing is vendored from upstream.

## What v1 does

- Reads a suite manifest (`suite.json`) describing test cases.
- Runs every case through one launcher bin, sequentially, in manifest order.
- Writes a flat results file (`flat-results.json`) into the output directory.

## Manifest schema

```json
{
  "name": "visible",
  "cases": [
    {"id": "auth-basic", "launcher": "unit", "duration_ms": 340, "deps": []}
  ]
}
```

Fields per case:

- `id`        unique string
- `launcher`  logical launcher the case belongs to (free-form tag)
- `duration_ms` nominal duration in milliseconds (positive integer)
- `deps`      list of case ids that must pass before this case may run

See `instruction.md` for the full extension contract (sharding, bail mode,
reporting) that this runner must grow into.