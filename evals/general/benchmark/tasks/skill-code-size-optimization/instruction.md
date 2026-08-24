code size optimization challenge. `/app/numbers.txt` contains one line with a single positive integer (digits only).

Write the shortest Python source file you can, `/app/one.py`, that:

- reads the integer in `/app/numbers.txt`,
- prints the **sum of its decimal digits** (e.g. `1234` → `10`) to stdout, and nothing else.

Constraints:

- The source file must be **no longer than 75 bytes** (80 columns of a typical editor are fine, but 75 bytes total is the hard limit — no comments, no docstrings, no long identifiers).
- It must produce correct output when run as `python3 /app/one.py` in any working directory.

Then run the script and confirm the printed number equals the digit sum. An example of the size you are aiming for (60 bytes):

```
print(sum(map(int,open('/app/numbers.txt').read().strip())))
```

Only the Python standard library is available.