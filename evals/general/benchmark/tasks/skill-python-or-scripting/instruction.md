# Python/scripting data transform

`/app/names.txt` contains one `NAME=VALUE` entry per line (no leading/trailing whitespace, no blank lines). Both names and values are simple ASCII tokens.

Write a small Python 3 script `/app/transform.py` and run it so that it creates `/app/out.txt`, a transform of the input with these exact rules:

1. Parse each line into a name and an integer value.
2. Keep only entries whose value is **even**.
3. Sort the kept entries by name **ascending** (standard lexicographic string order).
4. Write each kept entry as one line `name:value` (colon separator, no spaces), in sorted order, one per line.

Example: for input `Alice=30\nBob=25\n`, only Alice is kept and `out.txt` contains `Alice:30`.

When the script is done, `/app/out.txt` must exist and contain exactly the lines described.
