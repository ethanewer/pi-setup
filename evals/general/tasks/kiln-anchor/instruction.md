# kiln-anchor — the Kilnwatch gauge CLI

The **Kilnwatch** shop monitors pottery kilns with gauge loggers. You must
author a small C CLI, `kilnstat`, that reduces a gauge log into summary
statistics, build it to `/app/dist/kilnstat`, and install it so it is
invocable **by bare name from any directory** through the shell `PATH` (i.e.
typing `kilnstat ...` in a fresh non-login shell must work, not
`/app/dist/kilnstat ...`).

## Deliverables

1. `/app/src/kilnstat.c` — the C source of the CLI (compile with the system
   `cc`).
2. `/app/dist/kilnstat` — the compiled binary, built e.g. with:
   ```
   cc -std=c11 -O2 -o /app/dist/kilnstat /app/src/kilnstat.c -lm
   ```
3. The PATH install: `kilnstat <logfile>` must work from **any** working
   directory in a fresh non-login shell (`sh -c 'cd /tmp && kilnstat ...'`),
   and `command -v kilnstat` must resolve. The recommended route is a copy or
   symlink at `/usr/local/bin/kilnstat` (mode 0755); any mechanism that works
   under the default non-login `PATH` is acceptable.

## CLI contract

```
kilnstat <logfile>
```

Exactly one argument. The log is plain text; each line is one of:

- **Blank**: nothing or only whitespace — ignored.
- **Comment**: after optional leading whitespace, a `#` as the first
  character — ignored (even if the rest looks like data).
- **Reading**: exactly two whitespace-separated tokens
  `<HH:MM> <temperature>`.

Token rules:

- `HH:MM` must be a strict clock time: two digits `00`–`23`, a colon, two
  digits `00`–`59` (`12:60`, `24:00`, `9:30`, `009:30` are malformed).
- The temperature token must be a plain decimal real number: optional
  `+`/`-` sign, then digits with an optional decimal part or a dot-leading
  fraction, plus an optional decimal exponent — concretely the token must
  match `[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?` and nothing
  else (`7.`, `+.5`, `-3.5e2` are valid; `1.2.3`, `0x10`, `inf`, `nan`,
  `1_0`, `5C` are malformed). Any other shape makes the line **malformed**.

Malformed and ignored lines are **counted** (in `malformed`) but otherwise
skipped; readings keep file order.

### Output

Print exactly six lines to stdout and exit `0`:

```
samples=<N>
min=<%.3f>
max=<%.3f>
mean=<%.3f>
range=<%.3f>
malformed=<M>
```

- `<N>` = number of valid readings; `min`/`max`/`mean` (arithmetic mean,
  computed as sum of the values in file order divided by N) and
  `range` (`max - min`) formatted with exactly three decimals.
- **If `<N>` is 0** (no valid readings), print `min=NA`, `max=NA`,
  `mean=NA`, `range=NA` instead of numbers (still `samples=0` and the real
  `malformed` count).
- If the argument count is not exactly 1, print
  `usage: kilnstat <logfile>` to **stderr** and exit `2`.
- If the file cannot be opened, print a brief error to **stderr** and
  exit `1` (no stdout output).

## Visible data

`/app/data/shift-07.log` is a sample gauge log. Run your CLI on it as a smoke
test (the grader recomputes the same statistics independently):

```
kilnstat /app/data/shift-07.log
```

## How the grader probes it

- Executes `/app/dist/kilnstat` on the visible log and on **hidden gauge
  logs** you have not seen: comments and blanks anywhere, malformed tokens
  (bad clock times, junk suffixes, hex-ish tokens, underscores), negative and
  exponent-form temperatures, dot-fractions, a log with **zero** valid
  readings, and a missing-file case. It independently recomputes the six
  output lines from the documented rules and compares stdout exactly.
- Compiles `/app/src/kilnstat.c` from scratch with the documented `cc` line
  and requires the fresh build to behave identically on a hidden case.
- Requires bare-name invocation from a scratch directory and
  `command -v kilnstat` to resolve in a non-login shell.

Constraints: compile with the preinstalled `cc` only (plus `-lm`); no other
third-party libraries; no network anywhere.
