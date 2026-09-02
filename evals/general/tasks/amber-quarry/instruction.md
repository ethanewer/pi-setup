# Amber Quarry — solver verdict triage

The Amber Quarry scheduling office runs a constraint solver on haul plans. Each
run leaves a **transcript**; a triage tool must read the transcripts and decide,
for each one, whether the underlying constraint set was **satisfiable (SAT)**,
**unsatisfiable (UNSAT)**, or whether no usable verdict was emitted
(**NOVERDICT**).

Python 3.12 standard library only; no network access.

## Deliverables (both required)

1. `/app/verdict_scan.py` — a runnable Python 3 program:

   ```
   python3 /app/verdict_scan.py <log_dir> <out_file>
   ```

   It scans `<log_dir>` for files matching `*.log` (non-recursive) and writes one
   line per file to `<out_file>`, **sorted by filename** (lexicographic):

   ```
   <filename>:<TOKEN>
   ```

   where `<TOKEN>` is exactly one of `SAT`, `UNSAT`, `NOVERDICT`. For an empty
   directory the output file must exist and be empty.

2. `/app/verdicts_report.txt` — the report produced by running

   ```
   python3 /app/verdict_scan.py /app/case/logs /app/verdicts_report.txt
   ```

   on the shipped visible transcripts.

**Do not modify anything under `/app/case/`.**

## Classification rule

A **verdict line** is a line that, after stripping leading whitespace and
lowercasing, **starts with the word `verdict`**. Everything after that word is
the value: strip leading separator characters (spaces, tabs, `:`, `=`), strip
trailing whitespace, then strip trailing characters from the set `! . :`.

Map the value (already lowercased):

- `sat` or `satisfiable` → **SAT**
- `unsat`, `unsatisfiable`, `no solution`, `infeasible` → **UNSAT**
- anything else (including empty) → **NOVERDICT** (unrecognized verdict)

Deciding the verdict for one transcript:

1. Consider **only** verdict lines; any other line is noise even if it mentions
   `unsat`, `satisfiable`, `no solution`, etc. somewhere in its text (solver
   traces and comments love those words).
2. If there is **no** verdict line → **NOVERDICT**.
3. If there are several, the **last** one wins (later re-solves override).
4. Apply the value mapping above.

Examples:

- `verdict: SATISFIABLE` → SAT
- `  verdict = unsat` → UNSAT
- `VERDICT:INFEASIBLE` → UNSAT
- `verdict:sat.` → SAT (trailing period stripped)
- `# verdict: unsat` → **not** a verdict line (starts with `#`)
- `check: unsat-core retained` → noise, ignored
- a transcript with `verdict: sat` and later `verdict: no solution` → UNSAT
- a transcript with `verdict: maybe` → NOVERDICT

## Edge cases the grader probes (hidden transcript sets)

- Verdict lines with mixed case, extra whitespace, `=`/`:` separators, and
  trailing `.`/`!`/`:` punctuation.
- Noise lines that contain `unsat` / `UNSATISFIABLE` / `no solution` but do not
  start with `verdict` (including a verdict mention inside a `#` comment).
- Multiple verdict lines where the last must win.
- Transcripts with no verdict line at all, whitespace-only transcripts, and
  unrecognized verdict values → `NOVERDICT`.
- An **empty log directory** → empty output file.

The verifier re-runs your `/app/verdict_scan.py` unchanged on the visible and
hidden transcript directories and compares the report token-for-token.
