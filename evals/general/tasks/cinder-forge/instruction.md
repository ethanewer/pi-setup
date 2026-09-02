# BridgePay static security audit

You are a security engineer auditing the **BridgePay** batch-processing
service, a Python web service. The audit is delivered as a small, reusable
**static-analysis program** plus the findings it produces on the reference
source file. Your program will be executed unchanged on **hidden** source
files, so it must implement the documented rule contract generically — never
hard-code to the reference file.

Everything lives in `/app`. A verifier re-runs your artifacts in fresh
processes; nothing may depend on your current shell. Do not modify
`/app/billing_api.py`. Never read or depend on `/tests` or `/solution`.

## Deliverables (both required)

1. `/app/scan.py` — a runnable Python 3 program (standard library only) with
   this interface:
   ```
   python3 /app/scan.py <source.py> <output.json>
   ```
   It reads a Python source file and writes the findings report to
   `<output.json>`.

2. `/app/findings.json` — the report your program produces **on the provided
   reference file**:
   ```
   python3 /app/scan.py /app/billing_api.py /app/findings.json
   ```

## Rule contract

Each audited line is evaluated **independently, line by line**. Blank lines
and lines whose first non-space character is `#` are never findings. Input
files contain no triple-quoted strings, no semicolon-joined statements, and at
most one auditable call per line. Line numbers are 1-based over the physical
lines of the file.

For every line, apply each rule below. A rule matches at most once per line.

### 1. `hardcoded-credential` → CWE-798

A line is a finding if it is a **simple assignment** of the form
`NAME = <rhs>` or `OBJECT.NAME = <rhs>` (exactly one `=`, not `==`, no
augmented assignment) where:

- the assigned name (the final name component, case-insensitive) **contains**
  one of the substrings: `password`, `passwd`, `secret`, `token`, `api_key`,
  `apikey`, `access_key`;
- **and** the right-hand side is a **non-empty plain string literal**
  (single or double quotes; an optional `r`/`b`/`u` prefix is allowed; an
  `f`-prefixed literal or any expression is NOT a plain literal).

Assignments whose value comes from `os.environ`, a call, a variable, or any
non-literal expression are **safe**.

### 2. `command-injection` → CWE-78

A line containing `os.system(` or `os.popen(`. Take the **first argument** of
the call (the text up to the first comma at parenthesis depth 0 inside the
call's argument list). It is a finding **unless** that first argument is a
plain string literal (same literal definition as rule 1). So
`os.system("uptime")` is safe, while concatenation, f-strings, or a bare
variable are findings.

### 3. `sql-injection` → CWE-89

A line containing `.execute(`. Take the **first argument** of the call as
above. It is a finding **unless** the first argument is a plain string
literal. So fully parameterized calls like
`cur.execute("SELECT * FROM t WHERE id = ?", (uid,))` are safe (the first
argument is a literal), while `cur.execute(sql)`,
`cur.execute("... " + term)`, `cur.execute(f"...")`, or
`cur.execute(sql % uid)` are findings.

### 4. `unsafe-deserialization` → CWE-502

- A line containing `pickle.loads(` or `pickle.load(`: finding **unless** the
  first argument is a plain string or bytes literal (so
  `pickle.loads(b"\x80\x04...")` on a literal is safe, `pickle.loads(blob)`
  is a finding).
- A line containing `yaml.load(`: finding **unless** the call's argument list
  contains `Loader=yaml.SafeLoader` (or `Loader=SafeLoader`).
  `yaml.safe_load(` never matches and is always safe. `pickle.dumps` is
  never a finding.

### 5. `weak-hash` → CWE-327

A line containing `hashlib.md5(` or `hashlib.sha1(`. Any use is a finding.
`hashlib.sha256` and other strong hashes are safe.

## Output format

`<output.json>` must be valid JSON with exactly one top-level key:

```json
{
  "findings": [
    {"line": 17, "rule": "unsafe-deserialization", "cwe": "CWE-502"}
  ]
}
```

- Each finding has exactly the keys `line` (1-based integer), `rule` (one of
  the five rule names above), `cwe` (the exact CWE identifier from the
  mapping above).
- Findings are sorted by `line` ascending; ties (same line, several rules)
  by `rule` alphabetically. A file with no weaknesses yields
  `{"findings": []}`.
- A **wrong, missing, or misspelled CWE identifier fails the audit**, as does
  a wrong line number, wrong rule name, or a finding on a safe (decoy) line.

## Reference file

`/app/billing_api.py` is a realistic service module mixing vulnerable and
safe (decoy) lines — including commented-out patterns, literal-only calls,
parameterized queries, `yaml.safe_load`, `Loader=yaml.SafeLoader`, environment
sourced credentials, and strong hashes. Apply the rules exactly; do not
report decoys.

## Constraints

- The verifier runs `/app/scan.py` unchanged on hidden source files that
  follow the same contract, so the program must be fully generic.
- No network access at verify time; Python 3.12 standard library only.
- Do not modify `/app/billing_api.py`.
