# ledger-check

`ledger-check` is a gray-market ledger normalizer. It turns free-form receipt
amount strings into an exact integer count of cents.

## Public function

```text
normalize_amount(text: str) -> int
```

This is the single public function of the `ledgercheck` package. It returns the
number of cents represented by `text`, or raises `ValueError` when `text` is
empty, blank, or not a valid signed decimal amount.

### Contract details (the hidden verifier enforces every rule here)

* Surrounding whitespace is ignored: `" 12.00 "` -> `1200`.
* An optional leading `+` or `-` sign flips the sign of the result:
  `"-50"` -> `-5000`, `"+3.25"` -> `325`, `"-0.99"` -> `-99`.
* A single leading currency symbol among `$`, `€`, `£`, `¥` is stripped and
  ignored: `"$1,234.56"` -> `123456`, `"€99.99"` -> `9999`, `"£12"` -> `1200`.
* Comma is a thousands separator. Groups must be exactly three digits:
  `"1,000"` -> `100000`, `"1,000,000"` -> `100000000`; `"12,3"` and `"1,,000"`
  are invalid.
* A fractional part is allowed and must be preceded by a leading digit
  (`.5` is invalid; write `0.5`). The digit `0` is required before a leading
  decimal point: `"0.75"` -> `75`.
* Fractions longer than two places are rounded half-away-from-zero to the
  nearest cent: `"1.005"` -> `101`, `"2.675"` -> `268`, `"0.995"` -> `100`.
* Any number of digits is allowed with no thousands grouping
  (`"99"` -> `9900`, `"42.5"` -> `4250`).
* Empty and blank strings, stray symbols, and anything that is not a valid
  amount raise `ValueError`: `""`, `"  "`, `"abc"`, `"1.2.3"`,
  `"1,,000"`, `"5.1.2"`, `"$"`, `"-"`, `"12,345x"` all raise.

## Console entry point

```text
ledger-check
```

Reads a single line from standard input. On a valid amount it prints the
integer number of cents to stdout and exits `0`. On a malformed amount it
prints a diagnostic to stderr and exits `1`.

## Package metadata (must hold for the final wheel)

* `name`: `ledger-check`
* `version`: `0.4.2`
* `readme`: this file
* runtime dependencies: **none** — the wheel must install into an empty
  virtual environment with no network.

## Build

The project is a PEP 517 source layout. Build it offline into `/app/dist` with:

```bash
python3 -m pip wheel --no-build-isolation --no-deps -w /app/dist /app/pkg
```

The resulting wheel must be the only file `ledger-check` produces in
`/app/dist`.