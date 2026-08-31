# frost-marrow — forge the activation payload

The **frost-marrow** activation service expects a single payload line. The
recipe for computing it is scattered across a directory of plain-text
"artifact" files; you must combine them exactly as specified below. Your
program must work **on any artifact directory** that follows the documented
formats, not just the provided one.

## Environment

- Working directory: `/app`. It already contains the provided artifact
  directory `/app/artifacts/` (`serial.txt`, `pricebook.tsv`, `ledger.csv`,
  plus unrelated decoy files that must be ignored). Python 3.12 is available
  as `python3`.
- **Do not modify anything in `/app/artifacts/`.**

## Deliverables (both required)

1. `/app/forge.py` — a runnable Python program:

   ```
   python3 /app/forge.py <artifact_dir> [outfile]
   ```

   It reads the artifacts from `<artifact_dir>`, derives the payload by the
   rule below, prints the payload to **stdout**, and — when the optional
   `outfile` argument is given — also writes the payload followed by a
   single newline to that path. When `outfile` is omitted it writes the
   payload + newline to `/app/answer.txt`.

2. `/app/answer.txt` — the payload derived **from the provided
   `/app/artifacts/` directory** (i.e. the result of running your program on
   it without an explicit outfile).

## Artifact formats

- `serial.txt` — the **base value**: the first non-blank line is a single
  signed integer (leading/trailing whitespace tolerated). Any further lines
  are ignored. If the first non-blank line is not an integer, the program
  must exit non-zero with nothing on stdout.
- `pricebook.tsv` — unit prices, one entry per line: whitespace-separated
  fields `LABEL PRICE` where `PRICE` is a signed integer. Blank lines and
  lines whose first non-blank character is `#` are ignored. A line that does
  not yield `LABEL` + an integer price is skipped. If a label appears more
  than once, the **last** occurrence wins.
- `ledger.csv` — movement rows, comma-separated: `label,quantity` where
  `quantity` is a signed integer. Blank lines are skipped; a row whose first
  field is exactly `label` is a header and is skipped; a row with fewer than
  2 fields, or whose second field is not an integer, is skipped. A row whose
  label is **not** in the pricebook is skipped (it contributes nothing).
  Every valid row contributes — duplicate labels each apply.
- Any other file in the directory (e.g. `README.txt`, `notes.log`,
  `.gitkeep`) is not an artifact and must be ignored entirely.

## Derivation rule

```
total = base
for each valid ledger row (in file order):
    total += quantity * price[label]
payload = "OK-" + (total mod 100000), zero-padded to 5 digits
```

`mod` is Python's `%` on the signed integer `total`, so the residue is always
in `0..99999` (a negative total wraps). Example: base `17430`, rows
`alpha,12` / `beta,-4` / `gamma,7` with prices `alpha=250`, `beta=90`,
`gamma=-15` give `17430 + 3000 - 360 - 105 = 19965` → payload `OK-19965`.

## Edge cases the grader's hidden artifact directories probe

- Negative base values and negative totals (the mod wraps, e.g. total `-3`
  → `OK-99997`).
- Ledger rows with unknown labels, malformed rows, and a header row — all
  skipped without affecting the total.
- Duplicate pricebook labels (last one wins) and `#` comment lines.
- An empty or header-only ledger (payload comes from the base alone).
- Extra non-artifact files in the directory, ignored.

The verifier runs your program **unchanged** on each hidden artifact
directory and compares stdout to its own reference derivation, so do not
hard-code the provided files' contents or paths beyond the documented
defaults.

## Constraints

- No network access; standard library only.
- Deterministic: the same inputs always produce the same payload.
- Do not modify anything in `/app/artifacts/`.
