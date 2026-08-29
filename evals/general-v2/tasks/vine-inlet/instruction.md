# vine-inlet — repairing and pinning the hedge-station environment

You are the ops engineer for the **Hedge station** instrument cluster. The
on-site machine has a bundled Python virtual environment that was delivered
broken, an outdated data-reading library inside it, a frozen package manifest
that must not gain or lose anything, and a Node manifest that was shipped at
versions higher than the team wants. Your job is to repair and lock everything
down so the bundled tooling works.

Everything lives under `/app` on a Debian-based image with Python 3.12. Work
only inside `/app`; everything you need is already there.

## The layout (given, do not move or rename)

```
/app
├── env/
│   ├── .venv/                   # the Python virtual environment (broken as shipped)
│   └── constraints.txt          # read-only declaration of allowed top-level packages
├── garden_wheel/                # local flat wheel index (pip can install from here, offline)
│   ├── lotusfields-0.9.0-...whl
│   ├── lotusfields-0.7.0-...whl
│   └── coreclutch-0.5.0-...whl
├── node/
│   └── package.json             # npm manifest to be edited
└── tools/
    └── probe.py                 # bundled validator (do not modify)
```

## What is broken / what to fix

`/app/env/.venv` is a Python 3.12 virtual environment that ships broken in two
ways:

1. **pip is missing.** The `pip` module and every `pip`/`pip3`/`pip3.12`
   launcher were removed from the venv, so `python -m pip` inside it reports
   `No module named pip`. The interpreter is otherwise fine and its built-in
   `ensurepip` mechanism is intact, so the installer can be restored without
   touching the network.
2. **The bundled data library is too old.** The venv currently has
   `lotusfields==0.7.0` installed. That release does **not** accept the
   `dtype_backend=` keyword in `lotusfields.read_table(...)`. The validator
   `/app/tools/probe.py` calls `read_table(path, dtype_backend="tight")`, so
   the old release makes the probe crash. The new `lotusfields==0.9.0` wheel in
   `/app/garden_wheel/` supports that keyword.

`/app/env/constraints.txt` declares the **only** allowed top-level packages in
the venv, with their exact target versions:

```
lotusfields==0.9.0
coreclutch==0.5.0
```

You must therefore bring the venv so that `lotusfields` is upgraded to `0.9.0`
and `coreclutch==0.5.0` is importable — both from the local wheel index only
(no PyPI/network). No other packages may be added.

`/app/node/package.json` is shipped with the react-family at newer versions
than the team wants. You must **downgrade** the react family while leaving the
rest byte-for-byte untouched.

## Deliverables

1. **`/app/env/.venv`** — the repaired, upgraded venv. The verifier checks that
   `python -m pip --version` succeeds inside it, that `lotusfields.__version__`
   is `0.9.0`, that `coreclutch` imports, and that the probe harness runs on
   any input.
2. **`/app/pinned.txt`** — you create this text file. It must contain **exactly**
   these two non-empty lines (any order, trailing blank/whitespace lines allowed):
   ```
   lotusfields==0.9.0
   coreclutch==0.5.0
   ```
   It must contain **no other package names** — this file encodes the frozen,
   closed dependency set.
3. **`/app/node/package.json`** — edited as described below.

## The validator you must make work

`/app/tools/probe.py` is bundled and must **not** be modified. It is invoked as:

```
/app/env/.venv/bin/python /app/tools/probe.py <table.csv>
```

It reads a comma-separated table with a header row containing columns
`zone,height,flux`, and prints a single-line JSON result. Its exact contract
(verified against hidden inputs):

- **Valid table** → exit code `0`, output:
  `{"ok":true,"rows":<N>,"total_flux":<F>,"zones":[<sorted unique zone list>]}`
  where `N` is the number of data rows (header excluded), `F` is the sum of the
  `flux` column rounded to 3 decimals, and `zones` is the alphabetically sorted
  list of the unique `zone` values.
- **File does not exist** → exit code `3`, output `{"error":"not-found","code":404}`.
- **Any row has a non-numeric `flux`** → exit code `4`, output
  `{"error":"non-numeric-flux:row-<K>","code":422}` where `K` is the 1-based
  data-row number.
- **A required column is missing** → exit code `4`, output
  `{"error":"missing-columns:<names>","code":422}` (comma-joined missing names;
  e.g. only `flux` is missing → `missing-columns:flux`).
- **No data rows (header only)** → exit code `4`, output
  `{"error":"empty-data","code":422}`.

These exact strings, exit codes, and numeric values are what the verifier
compares, so the probe must reach these paths only after the venv is repaired
and upgraded (an outdated `lotusfields` makes it hit `{"error":"outdated-library"}`
instead).

## npm manifest requirements (`/app/node/package.json`)

The shipped manifest is:

```json
{
  "name": "hedge-wall-console",
  "version": "3.9.1",
  "private": true,
  "dependencies": {
    "@aws-amplify/lambda": "2.8.7",
    "aws-amplify": "6.7.0",
    "react": "19.5.0",
    "react-dom": "19.5.0"
  },
  "devDependencies": {
    "@aws-sdk/client-s3": "3.700.0",
    "@hedge/gauge-ribbon": "2.4.1",
    "@hedge/rivette-core": "1.9.0",
    "aws-sdk": "3.650.0",
    "react-native": "0.77.5"
  }
}
```

You must edit it so that **all three** of these hold:

1. **Only the react-family is downgraded, to these exact locked versions**:
   - `dependencies.react` → `"18.2.0"`
   - `dependencies.react-dom` → `"18.2.0"`
   - `devDependencies.react-native` → `"0.72.1"`
2. **Every other entry is byte-for-byte identical** to the shipped values —
   in particular the AWS-family entries (`@aws-amplify/lambda`, `aws-amplify`,
   `@aws-sdk/client-s3`, `aws-sdk`) and the `@hedge/*` entries must be
   **untouched**.
3. **The set of package names** in `dependencies` and in `devDependencies`
   must be exactly the same as shipped (no name added or removed — you only
   change the three version strings above). No version may be raised at all.

Preserve the manifest as valid JSON.

## Constraints / grading

- Work only in `/app`. Do not modify `/app/tools/probe.py`,
  `/app/env/constraints.txt`, the wheels in `/app/garden_wheel/`, or anything
  under `/tests`.
- Do not use PyPI or any network for the Python packages — everything comes
  from `/app/garden_wheel/` via pip (`--no-index --find-links`).
- The verifier re-runs `probe.py` (with the repaired interpreter) on several
  hidden tables — fresh valid tables plus empty, missing-column, and
  non-numeric edge cases — and checks the exact outputs above; it also parses
  `pinned.txt` and `/app/node/package.json` as described. Make sure your fixes
  hold for any well-formed input the probe can receive.
