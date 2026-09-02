# Diagnose a LaTeX compile log

## Context

`/app/run.log` is the transcript of a failed `pdflatex` run. It contains
several errors and warnings. Your job: find the **first** error and report it
as structured JSON.

An error in a TeX log appears as a line beginning with `!` (the message),
followed by a line `l.<number>` giving the source line number (or `<*>`
for command-line input).

## Your task

1. Scan `/app/run.log` for the **first** line that starts with `!`.
2. Read the following `l.<number>` marker for the source line.
3. Write `/app/out/error.json`:

   ```json
   { "line": <source line number, int>, "message": "<the error message text>" }
   ```

   e.g. `{ "line": 42, "message": "Undefined control sequence" }`.

## Success criteria

- `/app/out/error.json` exists and is valid JSON.
- `line` and `message` correspond to the first `!` error in `/app/run.log`
  (verified by re-parsing the log).