# Porting a grouped legacy COBOL report

In `/app` is a small **GnuCOBOL** payroll report program, `legacy.cob` (`PROGRAM-ID
REPORTGROUP`), together with `sample.dat` (fixed-width input) and
`sample_expected.txt` (the exact text GnuCOBOL emits when it runs on that sample).

Your task: work out precisely what the COBOL program does (including its **department
control-break subtotal logic**) and reimplement it as **Python 3** `/app/port.py`, so
that for any input file with the same 80-character layout, `port.py` writes **byte-for-byte**
the same report GnuCOBOL would write.

## Input record layout

One record per line, exactly **80 characters**, columns (1-based):

| Columns | Field       | Meaning                              |
|---------|-------------|--------------------------------------|
| 1-6     | id (9(6))               | employee id, zero-padded             |
| 7       | (blank)                 |                                      |
| 8-25    | name (X(18))            | employee name                        |
| 26      | (blank)                 |                                      |
| 27-28   | dept (9(2))             | department code, zero-padded         |
| 29      | (blank)                 |                                      |
| 30-34   | rate (9(3)V99)          | monthly rate, 5 digits, last two decimals |
| 35      | (blank)                 |                                      |
| 36-37   | yrs (9(2))              | years of service                     |
| 38      | (blank)                 |                                      |
| 39-43   | bonus (9(5))           | annual bonus, 5 digits, whole dollars |
| 44-80   | (blank filler X(37))    |                                      |

Your Python index slices are therefore: id `[0:6]`, name `[7:25]`, dept `[26:28]`,
rate `[29:34]`, years `[35:37]`, bonus `[38:43]`.

The input is pre-grouped: all records of a department appear one after another (in
whatever order the file gives); there are no department headers or trailers in the file.

## Per-record computation (integer fixed-point, truncation, not rounding)

Treat rate as cents (its 5 digits have two implicit decimals). For each record:

```
annual_cents  = rate * 12
incentive_cents = (bonus * 100) // years     when years > 0, else 0
total_cents   = annual_cents + incentive_cents
```

## Report output

For EVERY record write a detail line, exactly 46 characters wide, in this layout:

```
D<id:6> <name:18> <annual:09> <total:09>
```

Here `<id:6>` is the zero-padded 6-digit employee id, `<name:18>` is the 18-character name
verbatim, and `<annual:09>` `<total:09>` each mean: whole-dollar part zero-padded to 6
digits, then `.`, then the 2-digit cents remainder (9 characters total). The detail line
has no trailing space (`1 + 6 + 1 + 18 + 1 + 9 + 1 + 9 = 46`).

The report is **grouped by department** (the `dept` column). When a record's department
differs from the previous record's department, a *department subtotal* for the previous
department is written **before** that record's detail line. If all records share one department, no interleaved subtotal appears.

Department subtotal line, space-padded to exactly 46 characters:

```
S<dept:2> <dept-dollars>.<dept-cents>
```

where `<dept:2>` is the zero-padded 2-digit department code, `<dept-dollars>` is the
whole-dollar part of that department's summed `total_cents`, zero-padded to 8 digits, and
`<dept-cents>` is its 2-digit cents remainder. The content is `1 + 2 + 1 + 8 + 1 + 2 =
15` characters, then space-padded to 46.

After the final record, write (1) a department subtotal for the last department, and
(2) a grand-total line, space-padded to 46:

```
G<count:6> <grand-dollars>.<grand-cents>
```

`count` is the number of detail records; `grand-*` is from the sum of all `total_cents`
(whole dollars zero-padded to 8 digits). All lines end with `\n`, including the last.

## Verification contract

The hidden harness will:

1. Copy its own test input to `/app/port_input.dat`.
2. Compile the pristine reference `legacy.cob` (not the copy in `/app`, if you changed
   it) and run it against that test input to obtain the ground-truth report.
3. Run `/app/port.py` and compare its `/app/port_output.txt` to the ground truth
   **byte-for-byte**.

`port.py` must read `/app/port_input.dat` and write `/app/port_output.txt`. Use only the
standard library.

## Guidance

1. **Transcribe before coding.** Print the COBOL source and step through it; note exactly
   when `WRITE-DEPT-SUB` fires (a real control-break on the dept field) and when the
   grand line is emitted.
2. Verify against the sample: run `port.py` on `sample.dat` (as `port_input.dat`) and
   `diff` against `sample_expected.txt`. You may also compile and run the COBOL yourself
   (`cobc -free -x -o legacy legacy.cob`, then run `legacy` in a directory containing
   `data.dat`, which writes `report.txt`) to confirm your understanding.
3. Do not modify `legacy.cob`. Only write `port.py`. Byte parity including leading zeros
   and the trailing padding is mandatory.