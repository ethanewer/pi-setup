# Text processing

`/app/input.txt` is a plain-text file with several non-empty lines.

Write a Python script `/app/process.py` that reads `/app/input.txt` and writes
`/app/summary.json` containing exactly:

```json
{"words": <number of whitespace-separated tokens in the whole file>,
 "lines": <number of non-empty lines>}
```

Definitions are exact here:

- **words**: split the *entire file text* on any whitespace (spaces, tabs, newlines) and
  count the resulting tokens. Empty strings left by repeated whitespace are **not** tokens.
- **lines**: count lines that contain at least one non-whitespace character. A trailing
  newline should not create an extra empty line.

Use the standard library only (open, split, str.strip or similar). Run the script so
`/app/summary.json` exists with the correct counts. Leave `/app/process.py` and
`/app/summary.json` in place when you are done.