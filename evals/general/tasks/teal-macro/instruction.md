# Teal terminal — record Vim macros under a total keystroke budget

A pipeline stage rewrites ledger staging lines with Vim, but the deployment
platform only provisions a **tiny macro budget**. Your job is to record Vim
macro registers that perform the staging rewrite, with the combined length of
all defined macro registers at or under a hard keystroke ceiling.

Work under `/app`. Fixtures:

- `/app/source.txt` — the input file. Each line is exactly three
  comma-separated fields `WORD,NUMBER,WORD` where each `WORD` is one or more
  characters from `[A-Za-z0-9_]` and `NUMBER` is one or more digits. Field
  widths vary between lines. **Do not modify this file.**
- `/app/wanted.txt` — the required result of rewriting every line of
  `source.txt`: each line becomes
  `WORD3 WORD1 (NUMBER)`
  i.e. the third field, a single space, the first field, a single space, the
  second field wrapped in literal parentheses — nothing else changes, line
  count and line order preserved.

## Deliverables

1. **`/app/macros.vim`** — a Vimscript file that defines your macro registers.
   Requirements:

   - It must set macro **register `a`** (e.g. `let @a='...'`,
     `let @a="..."` or `setreg('a', ...)`). Register `a` is the *primary*
     macro and must be non-empty.
   - You may define additional registers `b`–`z` as helpers; they count toward
     the budget.
   - **Keystroke budget:** after the file is sourced, the sum
     `len(getreg('a')) + len(getreg('b')) + ... + len(getreg('z'))` over the
     registers you defined must be **at most 40 keystrokes**. The grader
     measures exactly this (via `getreg`, in characters). A macro that repeats
     many literal keystrokes, or one that hard-codes fixture text, will blow
     the budget.
   - The macro must be written against the **general format** above, not
     against the specific values in `source.txt` — the grader applies it to
     fresh hidden source files with different field values and widths.
   - `macros.vim` must **not** modify the buffer when sourced (defining
     registers is fine; editing is not).
   - `macros.vim` must not define functions, autocommands, mappings, custom
     commands, or interpreter bridges (`:python`, `:lua`, ...). The per-line
     work must be the recorded keystrokes themselves, and the grader checks
     the file text for these constructs.
   - Sourcing must be non-interactive and must not quit Vim.

2. **`/app/transformed.txt`** — the result you produced for the shipped
   fixtures by actually applying your macro to `/app/source.txt`; it must equal
   `/app/wanted.txt` exactly.

## How the grader applies your macro

In a clean headless Vim (`vim -Nu NONE -n -i NONE --not-a-term`) the grader:

1. `edit`s a source file (the shipped one, or a hidden one),
2. `source`s `/app/macros.vim`,
3. verifies the buffer was **not** modified by sourcing,
4. measures the budget: the sum of `len(getreg(x))` for `x` in `a`–`z`
   (must be ≤ 40, and `len(getreg('a')) > 0`),
5. applies your primary macro once per line:
   `:%g/^/normal @a`,
6. captures the resulting buffer and compares it byte-for-byte with the
   expected target for that source file.

Your macro will be applied to **hidden source files** too (different words,
numbers, widths — including a single-line file and fields containing
underscores/digits). It must transform every one of them exactly.

## Constraints

- The container ships `vim` (and `python3`); no network access.
- Do not modify `/app/source.txt` or `/app/wanted.txt`.
- Do not read `/tests` or `/solution`.
