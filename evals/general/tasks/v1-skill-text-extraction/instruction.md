# Text extraction probe: pull the largest numeric value

`/app/mixed.txt` is a plain text log that mixes prose with inline numeric
tokens (integers and decimals, possibly with `$` or `%` prefixes). You need to
**extract** the numeric values from the text and answer a simple question about
them.

Treat a "numeric value" as the first maximal run of the characters
`0-9` and `.` occurring in the text. In other words, a numeric token is the
longest substring starting and ending with a digit, containing only ASCII
digits and periods. Ignore commas, currency symbols, `%`, and surrounding text.

Read `/app/mixed.txt` and compute:

1. `token_count` — how many such numeric tokens appear in the file.
2. `largest` — the **largest decimal** (floatiest numeric value) among those
   tokens.

Write these to `/app/answer.json`:

```json
{
  "token_count": 8,
  "largest": 129.98
}
```

Compute the values from the actual file contents. Use a regex like
`[0-9.]+` to find the tokens (iterate over matches, skipping empty strings like
a bare `.`). Edge case: treat each match as its `float` value; tokens that do
not parse as a float (e.g. a lone `.`) should be discarded.