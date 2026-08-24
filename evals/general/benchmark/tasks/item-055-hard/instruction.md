# Item-055: Sum a column of integers

`/app/input/data.txt` contains a list of non-negative integers, one per line.
There is no header and no blank line.

Write a Python program `/app/solve.py` (Python 3, standard library only) that:

1. Reads the integers from `/app/input/data.txt` (ignore any trailing newline).
2. Computes their sum as an exact integer.
3. Writes the result (as a base-10 integer, no quotes, no trailing text) to
   `/app/answer.txt`.

Run it once so `/app/answer.txt` exists, e.g.:

```bash
python3 /app/solve.py
```

The verifier will independently re-read `/app/input/data.txt`, recompute the
sum, and compare it with the contents of `/app/answer.txt`. Do not hard-code
guessed values — sum the actual numbers in the file.