# Porting a legacy COBOL report

In `/app` you are given:

- `legacy.cob` — a small **GnuCOBOL** program (`REPORTGEN`).
- `sample.dat` — a sample input file of fixed-width records.
- `sample_expected.txt` — the report that GnuCOBOL writes when `legacy.cob` runs on
  `sample.dat`.

Your job: understand exactly what the COBOL program does with the input records, and
reimplement it in **Python 3** as `/app/port.py` so that for ANY input file with the same
record layout, `port.py` writes **byte-for-byte** the same report (same characters,
including spaces and leading zeros, in each line) that the COBOL program would write.

## The input record layout

`sample.dat` is UTF-8/ASCII text. Every line is exactly **80 characters** wide and is one
record. The field positions (1-based) are:

| Columns | Field      | Picture      | Meaning                                  |
|---------|-----------|--------------|------------------------------------------|
| 1-6     | EMP-ID    | 9(6)         | employee id (zero-padded digits)         |
| 7       | (blank)   |              |                                          |
| 8-25    | EMP-NAME  | X(18)        | 18-character name field                  |
| 26      | (blank)   |              |                                          |
| 27-31   | RATE      | 9(3)V99      | monthly rate, **5 digits**, last two are decimals |
| 32      | (blank)   |              |                                          |
| 33-34   | EP-YEARS  | 9(2)         | years of service                         |
| 35      | (blank)   |              |                                          |
| 36-40   | BONUS     | 9(5)         | annual bonus amount, **5 digits** (whole dollars) |
| 41-80   | FILLER X(40) | (ignored)   |                                          |

So `cols[0:6]` is a 6-digit integer, `cols[7:25]` is an 18-character name,
`cols[26:31]` is a 5-digit rate, `cols[32:34]` is a 2-digit years value, and
`cols[35:40]` is a 5-digit bonus amount. Every one of these is a fixed slice of the line.

## What the COBOL computes (replicate this exactly)

The COBOL data flow is (all arithmetic is integer / fixed-point with 2 implicit decimals,
with *truncation toward zero*, not rounding, for division):

1. **Annual = RATE x 12** in dollars-and-cents. The RATE field has two implicit decimal
   digits, so reading the 5 characters as the integer `R` means the monthly rate is
   `R/100` dollars. The annual gross is `(R x 1200)` *cents*.
2. **Incentive** = `BONUS / YEARS` in dollars, then converted to cents:
   `(BONUS x 100) / YEARS` (truncating, not rounding, division toward zero). If any
   record has `YEARS == 0`, the incentive for that record is `0` (no division).
3. **Total = Annual + Incentive** (cents).
4. For the annual field display one splits the cents into whole dollars
   `annual_cents // 100` and cents remainder `annual_cents % 100`.
5. For the total, likewise split `total_cents // 100` and `total_cents % 100`.

## The output line format

For each input record, exactly one output line is written, **45** characters wide
(GnuCOBOL writes the `PIC X(46)` record as a line-sequential file, which trims
its trailing pad space, leaving the 45 payload characters plus the newline):

```
<EMPIN[6]><SPACE><NAME[18]><SPACE><ANNUAL-DOLLARS[6]><DOT><ANNUAL-REM[2]><SPACE><TOTAL-DOLLARS[6]><DOT><TOTAL-REM[2]>
```

where:

- `EMPIN` is the zero-padded 6-digit employee id.
- `NAME` is the 18-character name field verbatim.
- `ANNUAL-DOLLARS` is the whole-dollar part of annual, **zero-padded to exactly 6 digits**.
- `ANNUAL-REM` is the cents remainder, zero-padded to exactly 2 digits.
- `TOTAL-DOLLARS`, `TOTAL-REM` are the same for the total.

The concatenation above is **45** characters; write exactly those 45 characters
followed by `\n`. Lines are terminated by `\n`. The last line also ends with a
newline.

So for the first sample record you would produce:

`000001 ADA LOVELACE       000990.00 009990.00\n`

## Deliverable

Write `/app/port.py`. It must read the input file from **`/app/port_input.dat`** and
write the report to **`/app/port_output.txt`**. Use only the Python standard library.

A hidden harness will supply an input file with the same 80-character layout at
`/app/port_input.dat`, compile and run the pristine GnuCOBOL program (the same one in
`/app/legacy.cob`) on it, and compare its output grep to `/app/port_output.txt`
**exactly, byte for byte, line by line**. You must match line counts, leading zeros, the
single space between fields, and the newline termination (no trailing pad space).

Suggested steps:

1. **Reverse-engineer** `legacy.cob` line by line; note exactly which fields each record
   touches and how the numeric pictures store the two implicit decimals.
2. **Prove** your model against the sample: run `port.py` on a copy of `sample.dat`
   (renamed to `port_input.txt`) and diff against `sample_expected.txt` until they match
   exactly. You can also compile GnuCOBOL yourself:
   `cobc -x -o legacy legacy.cob`, then run `legacy` in a directory holding `data.dat`;
   it writes `report.txt`.
3. Then generalise, keeping every slice and full integer-cents arithmetic exactly as the
   COBOL does. Handle `YEARS == 0` as "no incentive".

Do not change `legacy.cob`; only write `port.py`. Byte-for-byte parity is mandatory.