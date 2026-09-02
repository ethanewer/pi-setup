# Latency / throughput accounting

`/app/transfers.json` is a JSON array of transfer records:

```json
{"name": "<id>", "bytes": <int>, "duration_sec": <float>}
```

Compute two aggregate metrics over all records:

1. **Throughput** = `total_bytes / total_duration_sec` in bytes per second, where the totals sum over every record.
2. **Average latency** = mean of the per-record `duration_sec` values.

Write `/app/metrics.json`:

```json
{"throughput_bps": <float rounded to 3 decimals>, "avg_latency_sec": <float rounded to 3 decimals>}
```

Use Python's `round(x, 3)` for the rounding; use the plain computed value (do not normalize units further).

Implementation hint:

```python
import json
recs = json.load(open('/app/transfers.json'))
total_bytes = sum(r['bytes'] for r in recs)
total_dur   = sum(r['duration_sec'] for r in recs)
avg_lat     = total_dur / len(recs)
out = {
    "throughput_bps": round(total_bytes / total_dur, 3),
    "avg_latency_sec": round(avg_lat, 3),
}
json.dump(out, open('/app/metrics.json', 'w'))
```

Afterward `/app/metrics.json` must be valid JSON with those two numeric values.