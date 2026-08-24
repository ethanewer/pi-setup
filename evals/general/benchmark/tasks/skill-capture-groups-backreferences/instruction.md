/app/words.txt contains one lowercase English word per line (no other text). Write `/app/find.py` that:

1. reads all words,
2. uses a **regex with a capture group and a backreference** — the pattern `(\w)\1` — to find which words contain at least one doubled (identical adjacent) letter,
3. for every matching word, records the **first doubled letter** (the character captured by the group),
4. writes `/app/doubles.json` containing exactly:

```json
{
  "matched": ["<every matching word, in the order they appear in words.txt>", ...],
  "letters": { "<word>": "<first doubled letter>", ... }
}
```

For example, for the word `bookeeper` the doubled letters are detected by the backreference, and the first one is `o`.

Then run your script so `/app/doubles.json` is produced. Use only the Python standard library (`re` is allowed).