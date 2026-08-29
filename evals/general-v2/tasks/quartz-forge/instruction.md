# Quartz Forge — daily operations pack

You are the automation engineer at **Quartz Forge**, a quartz refining facility in the
California desert. Every morning the plant writes a `config.json` file describing the
previous day's telemetry and a candidate investment. Your job is to build ONE reusable
Python generator, `/app/forge_report.py`, that turns any such config into the day's
operations pack: a telemetry report, an investment decision, a one-line result record,
a JPEG heat-poster, and a designed construct sequence.

The facility ships you a config at `/app/data/config.json`. You must:

1. Write the generator `/app/forge_report.py` per the specification below.
2. Run it so it produces the artifacts in `/app`.
3. **Read the config from disk every run** — do not hardcode this one day's numbers.
   A verifier will re-run your generator on other config files (with different sites,
   counts, investment parameters, phrases, and length ceilings) and compare every
   produced artifact byte-for-byte against reference outputs. Anything hardcoded to
   the visible values will fail those checks.

## Input config schema (`/app/data/config.json`, JSON)

```json
{
  "records": [
    {"site": "Kingman", "count": 950, "frame_l": 3101, "frame_m": 2988, "frame_r": 2404}
  ],
  "investment": {"capex": 120000.0, "cashflows": [40000.0, 55000.0, 70000.0], "rate": 0.10},
  "phrase": "QUARTZ FORGE",
  "max_construct_len": 400
}
```

- `records`: a list of telemetry records. Each record has `site` (string) and
  integer fields `count`, `frame_l`, `frame_m`, `frame_r`. Site names may contain
  uppercase and lowercase letters only (no spaces). Record order in the file is
  arbitrary and must not influence the outputs (all outputs are deterministic from
  the data set as a whole).
- `investment`: a dict with `capex` (float), `cashflows` (list of floats), `rate`
  (float discount rate).
- `phrase`: short title string (uppercase and spaces) to render onto the poster.
- `max_construct_len`: non-negative integer, the length ceiling for the construct.

## CLI contract

`/app/forge_report.py` must be executable and accept an optional single argument:

```
python3 /app/forge_report.py              # uses /app/data/config.json
python3 /app/forge_report.py /some/config.json
```

Given a config path, it must (re)generate all five artifacts into `/app` and exit 0.

## Deliverables and exact output formats

All text artifacts are UTF-8 and must end in exactly one trailing newline. Every line,
space, and blank line counts — a single drift breaks the check.

### 1. `/app/report.txt` — headline stats and top-10 table (exact fixed-width)

- `TOTAL TRACES` = number of records.
- `UNIQUE SITES` = number of distinct `site` values.
- `TOTAL ANALYZED` = sum of `count` over all records.
- Table rows: sort records by `count` descending; ties are broken by `site`
  alphabetically ascending. List at most the top 10; if fewer than 10 records exist,
  list all of them (no filler rows).

Exact layout (showing the visible case; widths are fixed):

```
QUARTZ FORGE DAILY TELEMETRY
============================
TOTAL TRACES      :     7
UNIQUE SITES      :     7
TOTAL ANALYZED    :  3126

TOP-10 SITES BY TRACE COUNT

   1  Kingman         count= 950
     L: 3101  M: 2988  R: 2404
   2  Mojave          count= 731
     L: 1988  M: 1777  R: 1655
   ...
```

Construction rules (use exactly these):
- Line 1: `QUARTZ FORGE DAILY TELEMETRY`; line 2: exactly 28 `=` characters.
- Each stats line = label padded with spaces to width 18 (`ljust(18)`), then `": "`,
  then the integer right-aligned in 5 columns (`%5d`). Labels in order:
  `TOTAL TRACES`, `UNIQUE SITES`, `TOTAL ANALYZED`.
- Blank line.
- `TOP-10 SITES BY TRACE COUNT`, then a blank line.
- One block per row, in rank order:
  - Rank line: two leading spaces, rank right-aligned in 2 columns, two spaces,
    site name left-padded to 15 columns, ` count=`, then count right-aligned in
    4 columns → format `"  %2d  %-15s count=%4d"`.
  - Frame line: five leading spaces and three labelled values each right-aligned in
    5 columns, two spaces apart → format
    `"     L:%5d  M:%5d  R:%5d"` with `frame_l`, `frame_m`, `frame_r`.

### 2. `/app/decision.txt` — decision flags and objective (exact format)

Maximized NPV of the cashflows, discounted at `rate`, minus `capex`:

```
NPV = -capex + sum( cashflows[i] / (1 + rate) ** (i+1) )   for i in range(len(cashflows))
```

Round NPV to 2 decimals (Python `round(x, 2)`).
- `INVEST=yes` when rounded NPV `> 0`, else `INVEST=no`.
- `DEFER=yes` when not investing, else `DEFER=no` (i.e. `DEFER` is the opposite of
  `INVEST`).

Exact format (three lines, labels and values exactly as shown, NPV always two
decimals):

```
INVEST=yes
DEFER=no
NPV=14410.22
```

### 3. `/app/result.txt` — single-line result

Exactly one non-empty line:

```
RESULT=complete records=7
```

where `7` is replaced by the number of records. Ends with one trailing newline. No
other lines, no extra whitespace.

### 4. `/app/out.jpg` — JPEG heat-poster

A 900x200 RGB image with a solid black background `(0, 0, 0)`, the config `phrase`
drawn in white `(255, 255, 255)` at pixel position `(20, 80)`, using PIL's built-in
default font (`ImageFont.load_default()`), saved as JPEG at quality 90. Use Pillow:

```python
img = Image.new("RGB", (900, 200), (0, 0, 0))
d = ImageDraw.Draw(img)
d.text((20, 80), cfg["phrase"], fill=(255, 255, 255), font=ImageFont.load_default())
img.save("/app/out.jpg", format="JPEG", quality=90)
```

The phrase must come from the config; each config's poster is checked byte-for-byte
against the reference rendering of that config's phrase.

### 5. `/app/construct.txt` — designed construct within the length ceiling

The "construct" is the concatenation of the distinct site names in ascending
alphabetical order, with no separators:

```python
seq = "".join(sorted({r["site"] for r in cfg["records"]}))
construct = seq[: cfg["max_construct_len"]]
```

Write `construct` followed by a single trailing newline. The construct must never be
longer than `max_construct_len`. When the concatenation is shorter than the ceiling,
the whole concatenation is used; when longer, it is truncated to exactly the ceiling.
If the ceiling is 0, the construct is empty (the file is just the single newline).

## What must NOT be modified

Do not modify or delete anything under `/app/data/` except by reading it. (It is the
read-only input source.) Everything you write goes into `/app` or to files you create
in `/app`. Do not create files anywhere else.

## Tips

- After writing the generator, run it once with no arguments and inspect the five
  artifacts with `cat` / `xxd` / PIL to confirm exact formatting.
- Re-run your generator from a shell prompt after editing — it must work
  deterministically.
- The verifier will run your generator on other configs (including ones with more
  than 10 sites, equal-count ties, negative NPV, longer or shorter site sets, short
  length ceilings, and different phrases). Get the rules above exact so every hidden
  config reproduces the reference output byte-for-byte.
