Write `/app/args.py`, a command-line argument parser with the following interface contract:

Supported options:

- `--mode MODE` or `-m MODE` — a required string, one of `fast` or `slow` on the first run.
- `--count N` or `-c N` — an integer.
- `--label TEXT` — a free-form string (may contain spaces). The value may also be attached with `=` (e.g. `--label=two words`).
- exactly one positional argument FILE (a file path).

The parser must:

1. Accept options in any order, including interleaved with the positional FILE.
2. Accept both `--opt value` and `--opt=value` forms for the two long options.
3. Accept both long (`--mode`) and short (`-m`, `-c`) forms for `mode`/`count`.
4. Reject (print to stderr and exit non-zero) on an unknown option or a missing option value.

After parsing, the program writes `/app/parsed.json` containing exactly:

```json
{"mode": "<mode string>", "count": <int>, "label": "<label string>", "file": "<FILE path string>"}
```

Then verify by invoking the program with the following two argument lists (in turn) and confirming `/app/parsed.json` is correct each time:

```
/app/args.py --mode fast -c 7 --label=two words /tmp/file1.txt
/app/args.py --mode slow --count 3 --label no-spaces other.txt
```

Use only the Python standard library.