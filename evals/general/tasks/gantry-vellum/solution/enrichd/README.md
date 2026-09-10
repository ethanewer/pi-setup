# enrichd

`enrichd` is a streaming event-enrichment service.  Collectors across the
edge mesh push JSON-lines telemetry events into it over a pipe; enrichd
enriches every event with derived features of the client's recent behaviour
and a few pageview/purchase scalars, and writes one enriched object per
event to its output path.  It is deployed as a long-running process under a
supervisor that restarts it on crash and re-feeds the tail of the input on
restart, so steady-state memory behaviour matters as much as throughput.

Pure standard library.  No network access is required: all feature material
is derived deterministically from the client identifier.

## Layout

    enrichd/            service package
      cli.py            argument parsing and dispatch
      engine.py         the streaming input loop
      protocol.py       event schema, canonical client spelling, day math
      embed.py          deterministic feature material and digest fold
      fingerprint.py    digest -> published scalars
      cache.py          profile cache (daily behaviour digests)
      output.py         line-serialised output sink
      stats.py          runtime counters reported on stderr
    tests/              unit suite (python3 -m unittest discover -s tests -t .)
    workloads/          load fixtures

## Run

    echo '{"client": "Acct 001~b1", "ts": 1772140000, "kind": "login", "amount": 0.0}' \
      | python3 -m enrichd process --output out.jsonl

    python3 -m enrichd process --input workloads/visible.jsonl --output out.jsonl

The process reads one event per line from the input stream, enriches it, and
keeps going until the stream closes (or SIGTERM/SIGINT arrives), then drains,
flushes and exits 0.  Output is one JSON object per input event, in input
order, with the original fields plus the enrichment fields listed below.

## Enrichment contract

Per event with fields `client`, `ts` (epoch seconds), `kind`, optional
`amount`:

| Field          | Meaning                                                          |
|----------------|------------------------------------------------------------------|
| `client_key`   | canonical spelling of `client` (lowercase, collapsed whitespace, collector tag stripped) |
| `day`          | UTC calendar date of `ts`, ISO-8601 (`YYYY-MM-DD`)               |
| `segment`      | behaviour segment, integer 0..5                                  |
| `digest_mean`  | mean of the 2048-value daily behaviour digest, float             |
| `digest_energy`| sqrt(mean of squared digest values), float                       |
| `digest_l1`    | mean absolute digest value, float                                |

Floats are rounded to 6 decimal places.

## Development

    make test       # run the unit suite
    make smoke      # unit suite + a small run over workloads/visible.jsonl

The unit suite must stay green; nothing in it depends on wall clock or
network.
