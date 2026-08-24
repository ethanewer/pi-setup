# File I/O: read and write

`/app/input.txt` contains lines, each a single integer (one per line, possibly
with trailing whitespace or a blank trailing line):

```
3
-7
42
15
8
```

## Your task

Write a Python 3 script `/app/io.py` that:

1. opens and reads `/app/input.txt`,
2. parses every non-blank line as an integer,
3. computes:
   - `sum` = the arithmetic sum of the integers,
   - `count` = the number of integers,
   - `mean` = `sum / count` (a float),
4. writes `/app/output.txt` with **exactly three lines** (each ending in a
   newline):
   ```
   sum=58
   count=5
   mean=11.6
   ```

Then run the script so `/app/output.txt` exists. The verifier reads
`/app/input.txt` independently, recomputes the same values, and compares the
content of `/app/output.txt`.