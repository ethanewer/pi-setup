# A suppression comment that only works on the first line

`/app/src` is a real, unmodified working copy of **Bandit**, the security
static analyser for Python (the codebase as it was before one behavioral bug
was fixed — single commit, **no git history, no network**). The tree is fully
wired up: its own `bandit` command is installed on `PATH` and points at this
tree, Python 3.12.13 and the project's test dependencies (testtools, fixtures,
beautifulsoup4, ...) are installed, and the fix author's plan is deliberately
not told to you. You must localise the defect in the real tree, repair it, and
prove the repair with the project's own tools.

## The failing behaviour

When a finding covers a **multi-line** region of code — a triple-quoted string,
a `%`-formatting expression, a multi-line function call — placing the standard
`# nosec` suppression comment on **any line inside that region** is supposed to
silence the finding. It does not. Only a suppression comment on the **very
first line** of the region is honoured; a comment on the closing line (or any
middle line) is noticed (`bandit` even reports the comment in its "lines
skipped" accounting) yet the finding is still reported and the scan still
finishes with a failing exit status.

Reproduce it:

```bash
cd /app/src && bandit -q /app/repro.py; echo "exit: $?"
```

`/app/repro.py` is a multi-line string built with `%` whose `# nosec` comment
sits on the **closing** line of the expression. Right now you get:

```
>> Issue: [B608:hardcoded_sql_expressions] Possible SQL injection vector through string-based query construction.
   ...
   Location: repro.py:6:0
```

reported at the *opening* line of the construct, exit status 1, even though the
output's own accounting shows `Total lines skipped (#nosec): 1`.

## What to do

1. Run the reproducer and watch it fail.
2. **Localise** the defect. The cause is in the core scanner: the component
   that decides whether a finding is suppressed by a `# nosec` comment only
   consults the single line the finding was reported on, while the full line
   range of the construct is right there in the same context. Find that
   component by reading the core modules and by experimenting with small
   multi-line files of your own (SQL-style `%` strings, `exec(...)`,
   `eval(...)`, f-strings) that put `# nosec` on the closing or a middle line.
3. **Fix** it at the source so that a suppression comment anywhere in a
   finding's line range suppresses the finding, exactly as it does on the
   first line. Do not special-case particular plugins or input texts, do not
   disable checks globally, do not add post-processing that hides findings —
   the root cause is a small defect in the scanner core; repair the lookup
   itself.
4. **Prove** the fix with the project's own machinery, from `/app/src`:

   ```bash
   cd /app/src
   bandit -q /app/repro.py; echo "exit: $?"          # must now exit 0, no issues
   python3 -m unittest discover -s tests/unit -q                   # unit suite
   python3 -m unittest tests.functional.test_functional            # functional suite
   ```

   All three must pass. The suites each take only a couple of seconds.

## Deliverables

1. The repaired source tree in `/app/src` (ordinary file edits; keep every
   other file as-is).
2. `/app/diagnosis.md` — a short root-cause note (at least a few sentences)
   stating, in your own words: **where** the defect lives (which module of the
   scanner), **what** the code did wrong (why a comment on a later line was
   missed), and **the minimal fix** you applied.

Both are checked. If `/app/diagnosis.md` is missing or does not identify the
real module and cause, the task fails even if the tests pass.

## Constraints

- No network: the trial runs fully offline; everything you need is already in
  the image. Do not try to fetch or `pip install` anything.
- Do not modify the tree's `tests/` or `examples/` directories. The verifier
  runs the project's own test suites against your fixed tree and also compares
  the project's test files against their pristine content, so tampering with
  them to force a pass will be detected and scored as a failure.
- Do not delete or regenerate `/app/src`; repair it in place.

The expensive part is finding the defect, not running the checks — the whole
verification above takes seconds at one CPU.