# Organize files into folders by extension

`/app/loose/` contains 9 files with a mix of extensions:

```
alpha.py
beta.py
gamma.py
delta.csv
epsilon.csv
zeta.csv
eta.txt
theta.txt
iota.txt
```

There are no subdirectories inside `/app/loose/`, and every file has one of the
extensions `.py`, `.csv`, or `.txt`.

## Your task

Write a Python 3 script `/app/organize.py` that:

1. scans `/app/loose/`,
2. for each file, moves it into `/app/organized/<ext>/` (the subdirectory named
   after the file's extension without the leading dot), creating the
   subdirectory if needed. For example a file `foo.py` ends up at
   `/app/organized/py/foo.py`.
3. writes `/app/manifest.json` mapping each extension (e.g. `"py"`) to a sorted
   list of the filenames that were moved into that extension's directory.

After the script runs, `/app/loose/` must be empty (no lingering files or
directories), and all 9 files must be under the correct `/app/organized/<ext>/`

Run the script so `/app/manifest.json` exists.

The verifier walks `/app/organized/` and `/app/loose/` independently and checks
that every file ended up under the folder matching its extension, that
`/app/loose/` is empty, and that `/app/manifest.json` matches.