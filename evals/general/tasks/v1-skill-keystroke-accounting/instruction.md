# Keystroke accounting

`/app/keylog.json` has this structure:

```json
{"events": [ {"key": "<key name>", "press": <count>}, ... ]}
```

It records how many times each key was pressed (multiple events may reference the same key; sum their counts). Perform the accounting:

1. **Total keystrokes** = sum of all `press` values across all events.
2. **Distinct keys** = number of distinct key names that appear.

Write `/app/keylog_summary.json`:

```json
{"total_keystrokes": <int>, "distinct_keys": <int>}
```

Implementation hint:

```python
import json
d = json.load(open('/app/keylog.json'))
tot = sum(e['press'] for e in d['events'])
distinct = len({e['key'] for e in d['events']})
json.dump({"total_keystrokes": tot, "distinct_keys": distinct}, open('/app/keylog_summary.json','w'))
```

Afterward `/app/keylog_summary.json` must be valid JSON with the two exact integer values.