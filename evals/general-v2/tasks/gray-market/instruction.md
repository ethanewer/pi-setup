# Build the `ledger-check` wheel with correct metadata

You are packaging a small gray-market ledger normalizer. The package skeleton
already exists in **`/app/pkg`** (a PEP 517 project with a `src` layout), but
it is deliberately *incomplete*: the runtime dependencies metadata is missing,
the console entry point is not declared, and the public function body is a
stub. Your job is to finish the package so it builds into an installable,
correctly-declared wheel.

## What you must produce

1. **Complete `/app/pkg/pyproject.toml`** with a `[project]` section carrying
   exactly this metadata:

   - `name = "ledger-check"`
   - `version = "0.4.2"`
   - `readme = "README.md"`
   - **no runtime dependencies** (there is nothing under `[project]`
     `dependencies` and no `Requires-Dist` line in the built metadata)
   - a console-script entry point mapping `ledger-check` to
     `ledgercheck.cli:main` (under `[project.scripts]`)
   - setuptools settings so the `src/ledgercheck` package is discovered
     (`package-dir` pointing at `src` and `packages = ["ledgercheck"]`)

Keep the existing `[build-system]` table (`requirements = ["setuptools>=68"]`,
`build-backend = "setuptools.build_meta"`) as-is.

2. **Implement `normalize_amount(text)`** in
   `/app/pkg/src/ledgercheck/__init__.py`. The full contract is in
   `README.md`. It returns the integer number of cents for an amount string
   and raises `ValueError` for malformed input. The hidden verifier treats the
   README rules as the specification, so follow them exactly:

   - Trim leading/trailing whitespace: `" 12.00 "` -> `1200`.
   - Optional leading `+`/`-` sign changes the sign: `"-50"` -> `-5000`,
     `"+3.25"` -> `325`, `"-0.99"` -> `-99`.
   - A single leading currency symbol among `$` `€` `£` `¥` is stripped and
     ignored: `"$1,234.56"` -> `123456`, `"€99.99"` -> `9999`, `"£12"` ->
     `1200`.
   - Comma is a three-digit thousands separator: `"1,000"` -> `100000`,
     `"1,000,000"` -> `100000000`; mis-grouped commas such as `"12,3"`,
     `"1,,000"` are invalid.
   - A fractional part must be preceded by a digit: `".5"` is invalid, use
     `"0.5"` (`0.5` -> `50`), so `0` must precede a leading decimal point.
   - Fractions longer than two decimal places round half-away-from-zero to
     the nearest cent: `"1.005"` -> `101`, `"2.675"` -> `268`, `"0.995"` ->
     `100`.
   - A bare integer is allowed: `"123"` -> `12300`, `"99"` -> `9900`.
   - Empty/blank strings, stray symbols, and anything non-numeric raise
     `ValueError`: `""`, `"  "`, `"abc"`, `"1.2.3"`, `"5.1.2"`, `"$"`,
     `"-"`, `"12,345x"`.

Reading is a single-line console tool: when you have it working,
`printf '42.50\n' | ledger-check` must print `4250`; on invalid input it
prints a diagnostic to stderr and exits a non-zero status.

3. **Build the wheel offline** into `/app/dist` as the **only** file there:

```bash
python3 -m pip wheel --no-build-isolation --no-deps -w /app/dist /app/pkg
```

The `--no-build-isolation` flag is required so the build works without network
access. The resulting wheel file (e.g. `ledger_check-0.4.2-...whl`) is the
deliverable.

## Constraints

- **Do not modify** the following seeded files: `README.md`,
  `src/ledgercheck/cli.py`, and `src/ledgercheck/__main__.py`. The console
  script and module entry already call `normalize_amount`; only implement it.
- Do not touch anything outside `/app`.
- The verifier installs your wheel into a clean, empty, network-free virtual
  environment and then runs the installed package and the `ledger-check`
  command against exact-format edge cases and malformed-input checks. Version,
  entry point, and the empty dependency list are all part of the grade.

## Hints

- In the `src` layout the editable/source import is
  `from ledgercheck import normalize_amount`; the wheel must expose that same
  import path when installed.
- Only the wheel in `/app/dist` is graded, not your work files. Build it once,
  then sanity-run it: `printf '€9.99\n' | /path/to/your/venv/bin/ledger-check`
  should print `999`.