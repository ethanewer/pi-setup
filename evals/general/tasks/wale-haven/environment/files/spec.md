# Haven Grid monitoring specification

Haven Grid operates a regional network of smart meters. Each meter records one
event per reading: a timestamp to the exact second and a value in kWh (up to
three decimal places). The regional office needs, per monitoring period, the
total kWh recorded by the fleet during that period.

## Periods

A monitoring schedule is described by `periods.json`, a JSON object with a
single `periods` array. Every element is an object with exactly three string
fields:

| field  | meaning                                             | format                |
|--------|-----------------------------------------------------|-----------------------|
| `id`   | stable identifier for the period                    | any string            |
| `from` | start instant of the period                         | `YYYY-MM-DDTHH:MM:SS` |
| `to`   | end instant of the period                           | `YYYY-MM-DDTHH:MM:SS` |

Times are naive and represent UTC. The periods of one schedule are **consecutive
and non-overlapping**: the `to` of a period is exactly the `from` of the next
one, so together they cover one continuous monitoring span. Apart from the two
endmost instants of that whole span, every instant inside the span is covered by
exactly one period.

## Readings

Readings live in `events.csv`. The file has a single header row
`timestamp,value`, then one row per reading:

| column      | meaning                                   | format                |
|-------------|-------------------------------------------|-----------------------|
| `timestamp` | instant the reading was recorded          | `YYYY-MM-DDTHH:MM:SS` |
| `value`     | kWh recorded by the meter, may be decimal | number                |

## Attribution rule

The total of a period is the sum of the values of all readings whose timestamp
falls inside that period. The operations manual states only that a period
"covers the readings recorded from its start time to its end time" and does not
elaborate further.

## Data guarantees (every dataset, visible or fresh)

- Every row is well-formed: one timestamp, one numeric value.
- Every reading falls strictly between the first period's `from` and the last
  period's `to`; the data contains no reading exactly at either endmost instant.
- A reading is attributed to exactly one period. The per-period totals are
  therefore a partition of the fleet's readings: nothing is dropped and nothing
  is counted twice.

## Files

- `/app/spec.md`          — this document (do not modify)
- `/app/periods.json`     — the visible monitoring schedule (do not modify)
- `/app/events.csv`       — the visible readings log (do not modify)