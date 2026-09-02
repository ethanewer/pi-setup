# hinge-lathe — relay bulletin macro pass

The **Meridian Line** relay node publishes plain-text bulletins whose rows are
machined into a fixed layout by a headless vim macro pass. The pass used to
live on a decommissioned node; you must author a new one in `/app` and run it
against the shipped corpora. The transform is **byte-exact**: every
recognizable row is rewritten to a precise layout, and every other line is
passed through **byte-for-byte** unchanged.

## Environment

- Working directory: `/app`. The shipped corpora live under `/appdata/relay/`
  (`batch-1.txt`, `batch-2.txt`, `batch-3.txt`). `vim` and `python3` are
  installed. There is no GUI; everything is headless.
- Do **not** modify or delete `/appdata/relay/`.

## Deliverables (all required)

1. `/app/bulletin.vim` — one vim script (your macro pass), invoked headless:
   ```
   vim -es -N -u NONE -i NONE -n -S /app/bulletin.vim [file...]
   ```
   - With **no file arguments**, the script must transform every `*.txt` file
     directly under `/appdata/relay/` (non-recursive, ascending name order is
     fine but not checked).
   - With **explicit file argument(s)**, the script must transform exactly
     those files. The verifier inserts its own hidden `.txt` files this way
     and re-runs your script — behavior must follow the rules below on any
     conforming input, not just the shipped corpora.
   - In both modes every processed source file `<dir>/<name>` is written to
     `/app/outbox/<name>` (create `/app/outbox` if needed; same basename,
     regardless of the source directory).

2. The four visible outputs, produced by running your script on the shipped
   corpora:
   - `/app/outbox/batch-1.txt`
   - `/app/outbox/batch-2.txt`
   - `/app/outbox/batch-3.txt`

## Row grammar and transformation

Each line is processed independently. Two row dialects are **shapeable** and
must be rewritten; every other line must be left **byte-for-byte unchanged**.

### Ticket rows

Shapeable form (exactly three `|`-separated fields, no leading/trailing
whitespace on the line):

```
TKT-<digits>|<LOCATION>|<STATUS>
```

- `<digits>` — one or more decimal digits `0-9`.
- `<LOCATION>` — one or more **all-caps** words (`[A-Z]+`) separated by
  **single spaces** (so at least one character, no leading/trailing space,
  no double spaces, no other characters such as digits or hyphens).
- `<STATUS>` — one or more all-caps letters `[A-Z]+`.

**Transformation (exact):** rewrite to

```
<LOCATION> [TKT-<digits>] <STATUS>
```

Examples:
- `TKT-1041|BERTH GATE|OPEN` → `BERTH GATE [TKT-1041] OPEN`
- `TKT-42|PIER|HELD` → `PIER [TKT-42] HELD`

### Metric rows

Shapeable form:

```
load=<number>|<word>
```

- `<number>` — an optional minus sign `-`, then one or more digits, then a
  literal dot `.`, then **one to three** digits (the fraction). No plus
  sign, no spaces, no exponent.
- `<word>` — one or more lowercase letters `[a-z]+`.

**Transformation (exact):** rewrite to

```
load <word> <sign><digits>.<fraction padded to exactly 3 digits>
```

- `<sign>` is `-` if the input had a minus sign, otherwise `+`.
- The integer digits are kept **verbatim** (including any leading zeros).
- The fraction digits are **right-padded with zeros** to exactly 3 digits
  (`5` → `500`, `25` → `250`, `375` → `375`, `0` → `000`).

Examples:
- `load=3.5|north` → `load north +3.500`
- `load=-0.25|dock` → `load dock -0.250`
- `load=0.0|basin` → `load basin +0.000`
- `load=12.375|crane` → `load crane +12.375`
- `load=100.4|winch` → `load winch +100.400`

### Everything else — unchanged, byte-for-byte

Non-shapeable lines must never be touched. The hidden corpora probe many
near-misses; at minimum your pass must leave all of these untouched:

- blank lines and whitespace-only lines;
- comment/header lines starting with `# `;
- ticket rows with: a location containing a digit (`Yard 3`), a location with
  a leading or trailing space, a location with a double space, a
  non-all-caps status (`Open`), a lowercase `tkt-` prefix, an extra fourth
  field, or an empty field;
- metric rows with: no dot (`load=8|pier`), a dot but no fraction digits
  (`load=7.|swing`), a leading plus (`load=+1.5|dock`), a four-digit
  fraction (`load=1.2345|dock`), an empty word (`load=1.5|`), an uppercase
  or mixed word (`load=1.5|Dock`, `load=1.5|dock2`), a leading space in the
  word (`load=3.2| north`), an uppercase keyword (`LOAD=1.5|dock`), or
  trailing whitespace anywhere;
- any other line (e.g. a line that merely *contains* a row-like string after
  other text).

Note the byte-exactness requirement: a line that is passed through must not
gain or lose even a single character.

## Invocation recap

The verifier runs **exactly** this form (no GUI, no viminfo, no swap):

```
vim -es -N -u NONE -i NONE -n -S /app/bulletin.vim
vim -es -N -u NONE -i NONE -n -S /app/bulletin.vim /some/hidden/rows.txt
```

Outputs always go to `/app/outbox/<basename>`. Your script must therefore
create `/app/outbox` if it does not exist. All inputs are plain-text,
newline-separated ASCII; sources end with a trailing newline.

## Constraints

- No network, no GUI, nothing beyond `vim` and `python3` (python3 is
  available for inspection, but the transformation itself must be performed
  by the vim script when it is run as above).
- The verifier re-runs `/app/bulletin.vim` on hidden `.txt` files and checks
  the produced `/app/outbox/<basename>` files byte-for-byte (modulo trailing
  newline count) against an independent reference transform.

Write `/app/bulletin.vim` and run it on the shipped corpora so
`/app/outbox/batch-1.txt`, `/app/outbox/batch-2.txt`, and
`/app/outbox/batch-3.txt` exist and are correct.
