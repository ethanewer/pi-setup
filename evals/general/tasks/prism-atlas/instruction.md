# prism-atlas — fleet telemetry CLI tooling

The **Meridian Fleet Ops** group keeps four small utility scripts on its relay
node (`/app`). No GUI is available; everything is plain text and driven from a
shell. You will author four independent CLI tools/programs in `/app`, run them
against the provided fixture data, and leave both the programs and their
computed outputs in place.

There are **four** distinct parts. Read each contract exactly. A later,
independent verifier will RE-RUN your programs on new (hidden) inputs, so their
behavior must follow the documented rules below, not just reproduce one fixed
output file.

---

## Fixtures already present in `/app`

| Path | Contents |
|------|----------|
| `/app/data/calls/` | three `.log` files of call-site signatures, one signature per line (part 1) |
| `/app/state/state.txt` | the initial persistent-state value (parts 2 & 3) — a single integer, currently `17` |
| `/app/data/rows/` | plain-text depot files named `depot-a.txt` … `depot-d.txt` (part 4) |

Do **not** modify or delete these fixture directories (your programs read them;
the verifier will compare your outputs against them).

---

## Part 1 — aggregate & rank call-site signatures

Write a Python program `/app/rank_callsites.py` and run it to produce
`/app/callsite_rank.txt`.

**Interface (exactly):**
```
python3 /app/rank_callsites.py <input_dir> <output_path> [top_n]
```
- It scans **every regular file directly inside** `<input_dir>` (non-recursive,
  any extension). Files are visited in ascending filename order.
- Each text line is one call-site **signature**.
- **Counting rule (must be applied exactly):**
  - strip the trailing CR (`\r`) from a line's ending, then strip all leading
    and trailing whitespace;
  - a line that is empty **after** that stripping is *ignored* (never counted);
  - count occurrences of each resulting distinct signature.
- **Ranking rule:** sort signatures by **count descending**; signatures with
  **equal count** are ordered by their text in **ascending lexicographic
  (byte) order**. Truncate to the **top `top_n`** (default `10`) entries.
- **Output:** write `<output_path>` with the winning signatures one per line,
  each followed by a newline. If the input dir is empty (or yields no
  signatures), still create the output file — an empty file.
- If `top_n` exceeds the number of distinct signatures, every distinct
  signature is emitted.
- Exit status `0` on success.

Run:
```
python3 /app/rank_callsites.py /app/data/calls /app/callsite_rank.txt 10
```

**Edge cases (the verifier probes these):** blank lines and whitespace-only
lines are ignored; trailing spaces/tabs and CRLF line endings are stripped
before counting; ties at the top-10 boundary are resolved lexicographically
(byte order); a fully empty input directory yields an empty output file (the
file exists, contains no rows).

Your deliverable `rank_callsites.py` will be re-run by the verifier on a new
callsite corpus.

---

## Part 2 — CLI tool with persistent on-disk state

Write a Python program `/app/stateful_cli.py`. It is a **rolling counter** that
carries its value across **repeated separate invocations** in a **state file**.

**usage (exactly):**
```
python3 /app/stateful_cli.py <delta> [state_file]
```
- Default `state_file` is `/app/state/state.txt` (the fixture already contains
  its initial value: `17`).
- Each run:
  1. reads the **current** value from `state_file` — if the file is missing or
     empty it starts from `0`; otherwise parse the integer text (leading/trailing
     whitespace tolerated);
  2. adds `<delta>` (a signed integer; may be negative);
  3. writes the **new** value, as plain base-10 decimal text plus a newline,
     back to the **same** `state_file` (use atomic replace);
  4. prints the new value to stdout and exits `0`.
- **Critical:** the tool must **read the prior on-disk value** and accumulate on
  top of it. It must **never** reset to a fixed initial value. Running it twice
  with `5` then `9` must leave `y`, where `y = previous + 9`.

Demonstrate persistence by running it several times (see part 3).

Your deliverable `stateful_cli.py` is re-run by the verifier (fresh and repeated
invocations, negative deltas, and a missing initial state file).

---

## Part 3 — write the computed integer to `/app/out.txt`

The **computed integer** for this part is the final value of `/app/state/state.txt`
after you run the documented transaction sequence with `/app/stateful_cli.py`
(initial value = the fixture's `17`):

```
python3 /app/stateful_cli.py 5
python3 /app/stateful_cli.py 9
python3 /app/stateful_cli.py -2
python3 /app/stateful_cli.py 11
python3 /app/stateful_cli.py 8
python3 /app/stateful_cli.py 14
python3 /app/stateful_cli.py 0
```

Then read the resulting value of `/app/state/state.txt` and write it to
`/app/out.txt` **as text** (base-10 integer; a single trailing newline is fine,
other trailing whitespace is tolerated). The value must be **produced by
running the sequence**, not hard-coded. If the sequence is applied in exactly
that order from the fixture's initial state, the resulting integer is fully
deterministic — that is the value your output must equal.

**Output path is `/app/out.txt`** (not `output.txt`).

---

## Part 4 — transform plain-text files via a headless vim macro

Write a single headless vim script `/app/apply_macros.vim` and run it to
produce `/app/transformed/`.

**Row shape.** A **shapeable** row is a single line with **exactly three** `|`-separated
fields, all non-empty, and with no surrounding whitespace:

```
<field1>|<field2>|<field3>
```

**Transformation (exact):** every shapeable row is rewritten everywhere to:

```
<field2> (<field1>) <field3>
```

Every row that is **not** shapeable must be left **byte-for-byte unchanged**
(that includes empty lines, whitespace-only lines, lines with only one `|`
(too few fields), lines with more than two `|` (too many fields), and lines
with an empty field such as `a||b` or `|a|`).

**Invocation (headless, no GUI):**
```
vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim
```
With no file arguments, the script must transform **every `*.txt` directly
under `/app/data/rows/`** and save each result to `/app/transformed/<basename>`
(same filename). The script must also accept explicit source file path(s) as
arguments and transform those into `/app/transformed/<basename>` — the verifier
will insert its own hidden `.txt` files this way and re-run your script.

Produce the fixtures' four transformed files: `/app/transformed/depot-a.txt`,
`/app/transformed/depot-b.txt`, `/app/transformed/depot-c.txt`, and
`/app/transformed/depot-d.txt`.

**Examples (shapeable):**
- `104|Meridian depot|2207` → `Meridian depot (104) 2207`
- `9|Apex winch|88` → `Apex winch (9) 88`

**Unchanged examples:** `a||b`, `x|y`, `p|q|r|s`, blank line, `|a|xyz|`.

Your deliverable `apply_macros.vim` is re-run by the verifier on freshly
inserted hidden row files (valid rows plus edge/malformed rows).

---

## Summary of deliverables (all in `/app`)

1. `/app/rank_callsites.py` — runnable, executable Python script.
2. `/app/callsite_rank.txt` — the top-10 signature list (from part 1).
3. `/app/stateful_cli.py` — runnable rolling-counter CLI.
4. `/app/out.txt` — the computed integer from part 3.
5. `/app/apply_macros.vim` — headless vim macro script.
6. `/app/transformed/depot-a.txt`, `/app/transformed/depot-b.txt`,
   `/app/transformed/depot-c.txt`, `/app/transformed/depot-d.txt` —
   the transformed depot rows.

Make `rank_callsites.py` and `stateful_cli.py` executable (`chmod +x`). The
verifier invokes these programs directly, so they must not require arguments
your program does not accept, and must not depend on any files outside `/app`
(excluding the fixed fixtures). A program that only echoes a precomputed answer
instead of doing the real work will fail the hidden re-runs.