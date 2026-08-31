# ember-latch — normalize grid telemetry feed logs with a headless vim macro

The **Halcyon Grid Control** room ingests per-region telemetry feed logs as
plain-text pipe tables. There is no GUI on the control node — only a terminal —
so all normalization is done with headless `vim` driven by a macro script.
You will write one macro script and run it over the shipped feeds.

## Fixtures already present in `/app`

| Path | Contents |
|------|----------|
| `/app/data/feeds/feed-north.txt` | telemetry rows (part 1) |
| `/app/data/feeds/feed-south.txt` | telemetry rows |
| `/app/data/feeds/feed-east.txt` | telemetry rows |
| `/app/data/feeds/feed-west.txt` | telemetry rows |

Do **not** modify or delete anything under `/app/data/` — the verifier reads
these fixtures and compares your outputs against them.

## Part 1 — write the macro script `/app/apply_macros.vim`

**Row shape.** A **shapeable** row is a single line matching **exactly** this
shape (no leading/trailing whitespace):

```
<level>|<date>|<message>
```

where, in order:

1. `<level>` is one or more **lowercase** ASCII letters (`[a-z]+`);
2. a literal `|`;
3. `<date>` is a **zero-padded** calendar-style date `\d{4}-\d{2}-\d{2}`
   (four digits, dash, two digits, dash, two digits — no semantic calendar
   validation is performed);
4. a literal `|`;
5. `<message>` is one or more characters containing **no** `|`.

Any line that does not match this shape in full must be left **byte-for-byte
unchanged**. That includes empty lines, lines with too few or too many `|`
separators, uppercase levels (`INFO`), non-zero-padded dates (`2027-3-02`,
`02-03-2027`), levels containing digits/spaces, and empty messages
(`info|2027-03-02|`).

**Transformation (exact).** Every shapeable row is rewritten to:

```
<date> [<LEVEL>] <message>
```

where `<LEVEL>` is `<level>` converted to **uppercase**. The date comes first,
the level is bracketed and uppercased, and the message is kept byte-for-byte.

Examples:

- `warn|2027-03-01|voltage sag on bus 7` → `2027-03-01 [WARN] voltage sag on bus 7`
- `info|2027-03-04|feeder A restored` → `2027-03-04 [INFO] feeder A restored`

Unchanged examples: `INFO|2027-03-02|x`, `info|2027-3-02|x`,
`info|2027-03-02|`, `a|b`, `a|b|c|d`, blank lines.

**Invocation (headless, no GUI):**

```
vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim
```

With **no file arguments**, the script must transform **every `*.txt` file
directly under `/app/data/feeds/`** (sorted or not — every one of them) and
save each result to `/app/normalized/<basename>` (same filename; create
`/app/normalized/` if needed). The script must also accept **explicit source
file path(s) as arguments**:

```
vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim /some/hidden_feed.txt
```

and in that case transform exactly those files, writing each to
`/app/normalized/<basename>`. The verifier will insert its own hidden `.txt`
row files and re-run your script this way, so this argument mode must work.

## Part 2 — produce the shipped outputs

Run your macro script over the four shipped feeds so that these files exist and
are correct:

1. `/app/normalized/feed-north.txt`
2. `/app/normalized/feed-south.txt`
3. `/app/normalized/feed-east.txt`
4. `/app/normalized/feed-west.txt`

## Summary of deliverables (all in `/app`)

1. `/app/apply_macros.vim` — the headless vim macro script.
2. `/app/normalized/feed-north.txt`, `/app/normalized/feed-south.txt`,
   `/app/normalized/feed-east.txt`, `/app/normalized/feed-west.txt` — the
   transformed feeds.

## Constraints

- Only `vim` (headless) and standard shell tools are available; no network.
- The verifier re-runs `/app/apply_macros.vim` unchanged on hidden row files
  and compares its outputs **byte-for-byte** (modulo the trailing final
  newline) to the exact transformation defined above, so the script must
  implement the rule, not just reproduce the shipped outputs.
- Rows must be transformed in place order: output rows appear in the same
  order as the input rows.
