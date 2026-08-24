# Million-row CSV transform in Vim

You are operating as a data engineer. `/app/data.csv` is a comma-separated file
with **exactly 1,000,000 data lines** (plus a final trailing newline), and every
data line has exactly three fields:

```
<id>,<date>,<number>
```

where:

- `<id>` is a positive integer (first row is 1, increments by 1 each row),
- `<date>` is an 8-digit calendar date in `YYYYMMDD` form, e.g. `20240315`,
- `<number>` is a possibly-signed fixed/float value such as `872.19`.

## Goal

Use the **Vim editor** to transform every line so that the date field is
rewritten from `YYYYMMDD` to `YYYY-MM-DD`:

```
input :  123,20240315,872.19
output:  123,2024-03-15,872.19
```

The other two fields and their order are unchanged. There is **no header row**.
The output must have the same number of lines in the same order. Write the
result to `/app/out.csv`. Do **not** modify `/app/data.csv`.

## Approach guidance

The transformation must be performed *inside Vim* (`vim /app/data.csv`) — this is
the whole point of the task, not an awk/regex one-liner. Because there are a
million rows, first make the edit on a single line, **count the keystrokes** of
the per-row operation, then apply it across all rows. Two clean options:

1. **Recorded macro**: press `q` and a letter to begin, perform the per-row edit
   once, press `q` to end, then replay the macro across every row (e.g. jump to
   the first line and use a count, or run a `:normal`/global command that
   invokes it).
2. **Global command or substitute**: a single `:g/^/` (or a `:%s/.../.../`)
   command that rewrites the date on all lines at once.

When you are done, save `:w /app/out.csv` (or save-as to that path). Inspect the
head and the tail of the output to confirm all rows were transformed identically.

## Deliverables

1. **`/app/out.csv`** — the fully transformed 1,000,000-line output (exactly one
   line per input line; each date is `YYYY-MM-DD`; all other content identical).
2. **`/app/macro_recipe.txt`** — short ASCII notes describing the technique you
   used. It must contain:
   - a line stating the exact Vim command or the recorded macro keystroke
     sequence you executed (e.g. `:g/^/normal ...` or `q1...
   2 2q` style token), and
   - a line giving the keystroke / token count for the single-row operation.
   End with a newline.

## Verification

The grader independently recomputes the correct transformed content from
`/app/data.csv` and compares it line-by-line with `/app/out.csv`. It also checks
that `/app/macro_recipe.txt` exists, is non-empty, and documents a Vim
command/macro technique (it must contain a Vim command token).