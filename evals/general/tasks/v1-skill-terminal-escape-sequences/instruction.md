# ANSI terminal escape sequences

`/app/log.txt` already exists and contains three lines of server log text. Each line
begins with ANSI SGR (color) escape sequences that must be stripped before parsing.

Example line:
`\x1b[32mINFO:\x1b[0m started flow`

Write a Python program at `/app/extract.py` that:

1. Reads `/app/log.txt` as UTF-8 text.
2. Removes every ANSI escape sequence of the form `\x1b[ ... m` (the byte 0x1B
   followed by `[`, a possibly-empty run of `;`-separated decimal codes, and a
   trailing `m`). Use the regex `\x1b\[[0-9;]*[A-Za-z]`.
3. For each cleaned line, splits it into a level token (everything up to and
   including the first `:`) and the message (everything after that first `:`).
   The level token is the part before the `:`.
4. Writes `/app/clean.json`:

   ```json
   {
     "lines": [ {"level": "INFO", "message": " started flow"}, {"level": "WARN", "message": " retrying request"}, {"level": "ERROR", "message": " backend timeout"} ],
     "level_counts": {"INFO": 1, "WARN": 1, "ERROR": 1}
   }
   ```

   `lines` is an array with one object per input line, in order, with keys
   `level` and `message`. `level_counts` maps each observed level to its total
   count across all lines. Order of `level_counts` keys is not important.

Do not modify `log.txt`. The program must run and produce `/app/clean.json`.