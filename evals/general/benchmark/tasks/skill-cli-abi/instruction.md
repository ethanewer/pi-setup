Write `/app/prog.py`, a command-line program whose **public command-line interface contract (ABI) is fixed and must be matched exactly**.

The ABI is:

- `prog.py` takes one required positional argument FILE, and one optional flag `--name NAME` (a free-form string).
- With `--name NAME`: the program reads the text file at FILE and prints each non-empty line prefixed by `NAME ` (NAME + a space). With no `--name`, it prints each line unchanged.
- `prog.py --version` → prints the single line `myapp version 2.3.0` to stdout (nothing else) and exits 0.
- `prog.py --help` → prints usage text to stdout that contains the exact line `Usage: prog [--name NAME] FILE`, and exits 0.
- Any unknown flag (e.g. `--bogus`) → exits with a non-zero exit code and prints an error message to stderr.

The flag and FILE may be given in any order (flags do not need to precede the positional).

Then verify your implementation by running it the following way (creating a file `/app/demo.txt` with two lines `alpha` and `beta`):

```
python3 /app/prog.py --name ZED /app/demo.txt   # -> "ZED> alpha\nZED> beta\n"
python3 /app/prog.py /app/demo.txt              # -> "alpha\nbeta\n"
python3 /app/prog.py --version                  # -> "myapp version 2.3.0"
```

Use the Python standard library.