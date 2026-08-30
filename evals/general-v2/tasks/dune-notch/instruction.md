# Parse a deployment-roster bundle into a uniform TSV

Under `/app/data` you are given a **bundle of heterogeneous record files** for a
field-research deployment. Write one small, *general*, runnable Python 3 program
that reads any directory following the same contract below and emits a single
normalized TSV describing everything that can be derived. Then run it on
`/app/data` to produce the required output file.

## Deliverables (exactly two)

1. **`/app/parse.py`** — a runnable Python 3 program. It must implement every
   parsing/derivation rule below and be *general*: the verifier will run it on
   other input directories it provides (same filenames, different contents /
   edge cases), not just the shipped one.
2. **`/app/out.tsv`** — the TSV produced by running your own `parse.py` on
   `/app/data` (i.e. `python3 /app/parse.py /app/data /app/out.tsv`). This is
   your deliverable artifact.

## Command-line contract

```
python3 /app/parse.py [IN_DIR [OUT_TSV]]
```

- Default `IN_DIR` = `/app/data`; default `OUT_TSV` = `/app/out.tsv`.
- Every input directory (visible *and* hidden) contains **all** of the files
  below; you may assume they exist. The program must exit 0 and write the TSV.
- The output must be **deterministic** and require **no network access**.

## Output format (exact)

`OUT_TSV` is a TSV with **one record per line**, each of the form
`<type>\t<key>\t<value>` (three fields). A record's meaning depends on its
`type`:

| type     | key                | value                          |
|----------|--------------------|--------------------------------|
| `person` | person id          | `<first> <last>` full name     |
| `team`   | person id          | derived team name (rule below) |
| `born`   | person id          | ISO date `YYYY-MM-DD`          |
| `avg`    | person id          | mean of readings / `N/A`       |
| `pref`   | person id          | decoded preferred shift        |
| `city`   | `addr-N`           | extracted city name            |
| `tree`   | full relative path | kind label (dir/file/...)      |
| `qdp`    | column label       | column sum                     |
| `cnf`    | `vars`/`hard`/`soft`/`opt` | integer value            |

**Ordering:** sort the complete list of records **by `type`, then by `key`**
(both as plain string comparisons), and write one line per record. There must
be no blank lines and no trailing blank line. Values are written exactly as
shown below (no quoting of TSV fields, no extra whitespace).

---

## 1. `people.tsv` — tabular records → person / team / born / avg

Tab-separated, first non-blank line is the header. Column matching is **by
name** (case-insensitive, whitespace-trimmed), not by position; extra columns
may appear anywhere and any row is keyed by its `person_id`. The columns you
care about are `person_id`, `first`, `last`, `initials`, `institute`,
`birth_date`, `am`, `pm`, `ev`.

Blank lines and fully-blank data rows are ignored; a row that does not have the
same number of cells as the header is skipped (never crashes). A row whose
`person_id` is empty is skipped. For every valid row emit one record of each:
`person`, `team`, `born`, `avg`.

**`person`** value = `first` and `last` joined with a single space
(`first.last` → `first + " " + last`).

**`team` value (fixed scheme)** = `T-<INIT>-<INST>` where:
- `INIT` = for each whitespace-separated token in `initials`, take its **first
  character uppercased**; concatenate all of them (no separator). E.g.
  `d r` → `DR`, `mn` → `M`, `a j k` → `AJK`.
- `INST` = for each **alphabetic word** in `institute`, take its **first
  character uppercased**; concatenate (no separator). E.g.
  `Lunar Observatory` → `LO`, `Northwind` → `N`, `Iron Gate Works` → `IGW`.
- Separators and order are fixed: `T-` then `INIT`, then `-`, then `INST`.

(So `Bryn Kan` with initials `b k` at `Red Rocks` → `T-BK-RR`.)

**`born` value** = normalize the `birth_date` cell to ISO `YYYY-MM-DD`
(zero-padded), per the date rules in section 1a.

**`avg` value** = mean of the three numeric readings in `am`, `pm`, `ev`,
ignoring masked markers (section 1b). Format the mean as two decimals with
Python's fixed-point formatting (e.g. `f"{mean:.2f}"`; `9.75` stays `9.75`,
`6.875` → `6.88`, `-2.25` stays `-2.25`, `0.0` → `0.00`). A row whose readings
are **all** absent → value `N/A`.

### 1a. Date normalization (`born`)

`birth_date` may be one of these formats (a cell is a single trimmed token):
- `YYYY-MM-DD` or `YYYY-M-D` (already/generally ISO, may be non-zero-padded)
- `YYYY.MM.DD` / `YYYY.M.D` (dot separators)
- `MM/DD/YYYY` or `M/D/YYYY`
- `DD Mon YYYY` (three-letter or longer month name, case-insensitive;
  e.g. `5 Mar 2010`, `29 Feb 2016`)

Always emit the real calendar day in `YYYY-MM-DD` with zero-padded month and
day. If a date cell is **empty** → emit `--`. If it is present but **cannot be
parsed to a real calendar date** (e.g. month 13, a non-existent day like
`2015-02-29`, or an unsupported shape) → emit the literal `INVALID`. Leap
dates like `29 Feb 2016` and `2000-02-29` are valid.

### 1b. Masked markers (`avg`)

In the numeric reading columns `am`, `pm`, `ev`, a cell is **absent data** if
its trimmed, **lowercased** content is one of: `na`, `n/a`, `none`, `null`,
`nan`, `missing`, `-`, `--`, `nil`. Matching must be **case-insensitive**
(so `NONE`, `None`, `N/A`, `NaN` also count as absent). This is the key rule:
lowercase the cell before comparing with the sentinel set. Any cell **not** in
the masked set is parsed as a float (if it does not parse as a float it is also
ignored). `avg` = arithmetic mean of the cells that are present; all absent →
`N/A`.

---

## 2. Preference fixtures — `pref` (three encodings)

Decode the preferred shift out of **three** serialized files in the input
directory, then **merge** them into one `person_id → shift` map. Exactly one
of the files may map a given person; merge in the order JSON, then INI, then
YAML (later files override any earlier duplicate). Emit one `pref\t<id>\t<shift>`
record for every person in the merged map.

- `prefs.json` — a JSON object `{"person_id": "shift"}`.
- `prefs.ini` — an INI file; shift entries are `person_id = value` lines
  (whitespace around `=` and values trimmed); the section header (e.g.
  `[roster]`) is present but its name is irrelevant; `#`/`;` lines are comments.
- `prefs.yaml` — a simple YAML mapping of `person_id: shift` lines (may contain
  `#` comment lines and may be empty). Treat it as a mapping of strings to
  strings.

---

## 3. `addresses.txt` — `city` (city after the street-number line break)

Records are separated by one or more blank lines. Each **valid** record is
exactly three non-blank lines, in order: a street line, a street-number line,
and a city line. The street-number line is the one whose **first character is a
digit** (digits with a trailing letter like `7b`/`10C` are numbers too). Skip a
record entirely (contribute nothing) if it does not have exactly three non-blank
lines, or if its second line does not start with a digit. For each valid record,
in order of appearance, emit `city\taddr-<N>\t<city>` where `N` counts valid
records starting at 1 and `<city>` is the third line, trimmed of leading/trailing
whitespace (internal spaces preserved).

---

## 4. `dirlist.txt` — `tree` (parse a `tree -F` listing)

The file is a `tree -F`-style indented listing: each line is indented by 2
spaces per depth level, and the entry name may carry a **suffix character** that
denotes its kind:

| suffix | kind label |
|--------|-----------|
| `/`    | `dir`     |
| `*`    | `exec`    |
| `@`    | `symlink` |
| `|`    | `fifo`    |
| `=`    | `socket`  |
| (none) | `file`    |

A directory line opens a nesting level under which deeper-indented lines hang.
Entry names may contain special characters (spaces, `.`, `!`, `-`, `+`, etc.);
the kind suffix is the single **last** character when it is one of `/*@|=` and is
otherwise part of the name. Indentation determines parenthood (a line at depth
`d` belongs to the nearest preceding line at depth `< d`, which must be a dir).

Emit one `tree\t<full-relative-path>\t<kind>` record per entry, where the path
joins the entry name to all of its ancestor directory names with `/`. The root
directory itself is included. The trailing kind suffix is NOT part of the name;
internal special characters ARE preserved in the path.

---

## 5. `table.qdp` — `qdp` (lowercase-command ascii table)

An ascii table where **command and label lines are lowercase**. Rule set:

- Lines whose first whitespace-token, lowercased, is a command keyword
  (`read`, `serr`, `line`, `point`, `header`, `time`, …) are command lines and
  are skipped (they carry no data).
- A label line is `name <i> <label...>`; it names column index `i` with the
  label text (which may contain spaces) that follows. Column indices are
  non-negative integers.
- Any other non-empty line that is **all numeric tokens** is a data row; its
  tokens are the per-column values. A data row with a different number of
  columns than were named is skipped. Non-numeric, non-command lines are
  skipped.
- Number-of-columns = `max(named column index)+1`.

Emit one `qdp\t<label>\t<sum>` record per named column, in increasing column
index order, where `<sum>` is the sum of that column's values across data rows.
Write numeric values in plain form: integral floats as integers (`3.0` → `3`),
otherwise as Python `repr` of the float (`8.5` → `8.5`, `-3.0` → `-3`).

---

## 6. `instance.wcnf` — `cnf` (weighted CNF / MaxSAT)

The file is a weighted-CNF instance in WCNF text format:

```
p wcnf <nvar> <nclauses> <top>
<weight> <lit> <lit> ... <lit> 0
```

- The header line starts with `p wcnf`.
- Each following line is one clause: a positive integer `weight`, then a list of
  non-zero integer literals (positive = variable, negative = negated), ending
  with `0`.
- A clause whose `weight == top` is a **hard** clause; all others are **soft**.

Emit four records:
- `cnf\tvars\t<nvar>`
- `cnf\thard\t<number of hard clauses>`
- `cnf\tsoft\t<number of soft clauses>`
- `cnf\topt\t<optimal MaxSAT objective>`

`opt` = the minimum, over all boolean assignments to the `nvar` variables, of the
sum of weights of the **unsatisfied soft clauses**, subject to **all hard
clauses being satisfied** (an assignment that breaks a hard clause is
infeasible). If no assignment satisfies every hard clause, `opt = top`. The
variables are `1..nvar` (some may not appear in any clause — they are still free
variables and part of the assignment space). A clause is satisfied when at least
one of its literals is true under the assignment.

---

## Edge cases the hidden inputs probe

The verifier runs your parser on fresh input directories covering this range.
Make sure your program handles all of them without crashing and with exact
output (this list documents the intended behavior, which the rules above
already define):

- **Dates:** already-ISO, non-padded `YYYY-M-D`, dot-separated `YYYY.M.D`,
  `M/D/YYYY`, `DD Mon YYYY`, leap days, month 13, a non-existent day (e.g.
  `2015-02-29`), and an unparseable token → `INVALID`; an empty cell → `--`.
- **Masked markers:** uppercase and mixed-case variants (`NONE`, `None`, `N/A`,
  `NaN`, `NULL`, `nil`, `missing`, `--`, `-`) must all count as absent; a row
  with every reading masked → `avg N/A`; a lone `-` is a masked marker, not a
  number.
- **people.tsv:** extra columns present, an entirely-blank data row, a row with
  the wrong cell count (skipped), initials in any case, single-word and
  multi-word institutes.
- **Prefs:** an empty JSON object, an empty/comment-only YAML, values with
  spaces around `=`, persons spread across the three encodings.
- **Addresses:** multi-word city names, number lines with trailing letters,
  a 2-line block, and a block whose second line is not a number — the malformed
  blocks are simply skipped.
- **Tree:** names with spaces and special characters, `exec`/`symlink`/`fifo`/
  `socket` suffixes, deeper nesting.
- **QDP:** extra `serr` command lines, negative and fractional data, fewer named
  columns than data columns, multi-word labels, a table with **no** data rows
  (column sums are `0`).
- **WCNF:** all-hard instances (`soft=0`, `opt=0`), unit weights, a variable
  that appears in no clause, clauses whose weights are soft but not the
  arithmetic optimum that a naive parser would guess.

## Rules

- Do **not** modify, rename, or delete anything already under `/app/data`.
- Make **no changes** to the device other than creating `/app/parse.py` and
  `/app/out.tsv`.
- The program must read its inputs from the argument directory and write the TSV
  to the requested path. It must not assume this specific bundle's bytes beyond
  the documented contract, and it must be runnable on any directory produced
  under the same contract.
- No network access.
