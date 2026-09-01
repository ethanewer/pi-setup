# Regex escaping for literal matching

`/app/data.json`:

```json
{
  "text": "price $5.00 and $5.00 (item) total",
  "tokens": ["$5.00", "(item)"]
}
```

Write `/app/esc.py` that, for each token, counts how many **literal** (non-overlapping)
occurrences of that token appear in `text`. The tokens contain regex metacharacters
(`$`, `.`, `(`, `)`), so they must be escaped before being used in a regex — use
`re.escape(token)` — otherwise `(` would open a group, `$` would anchor to end-of-line,
and `.` would match any character, giving wrong counts (or a regex error).

Compute counts with `len(re.findall(re.escape(token), text))` and write
`/app/result.json`:

```json
{"counts": {"$5.00": 2, "(item)": 1}}
```

Run `python3 /app/esc.py` so the file is produced. The verifier recomputes the same
counts with `re.escape`; do not hardcode.