# Static weakness review of a legacy web service — map findings to CWE ids

You are a security auditor. The legacy **report service** source must be
reviewed for security weaknesses, and every weakness must be reported with the
exact **Common Weakness Enumeration (CWE)** identifier from the catalog below.

Everything you produce lives in `/app`. The verifier re-executes **your**
program in fresh processes against hidden source files, so `/app/solve.py`
must be a general analyzer that works on **any** input module following the
rules below — never hard-code the provided fixture.

Read-only fixture under `/app` (do NOT modify):
* `/app/report_service.py` — the legacy service source to review.

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python 3 program (standard library only):
   ```
   python3 /app/solve.py <source_file.py> <output_json>
   ```
   It parses the given Python source file and writes a JSON findings report to
   the output path.

2. `/app/answer.json` — the report your program produces for the provided
   fixture:
   ```
   python3 /app/solve.py /app/report_service.py /app/answer.json
   ```

## Output JSON format

```json
{
  "findings": [
    {"component": "<function name>", "cwe": "CWE-XXX"},
    ...
  ]
}
```

* Each finding is attributed to the **nearest enclosing function** (`def` or
  `async def`) by its plain function name. Code at module top level uses the
  component name `"<module>"`. Nested functions attribute to the innermost
  enclosing function.
* At most **one** finding per `(component, cwe)` pair, even if the pattern
  occurs several times in that component.
* `findings` is sorted by `component`, then by `cwe` (plain string order).
* Components with no weakness appear nowhere in the report.

## The weakness catalog (allow-list — these and ONLY these count)

A "string literal" means a plain constant string in the source (an
`ast.Constant` holding `str`). F-strings, string concatenation, `.format()`
results, and variables are all **not** string literals. The source is analyzed
statically; the file is never executed.

| Rule | CWE | Trigger |
|---|---|---|
| R1 | `CWE-89`  | A call whose attribute name is `execute` (e.g. `cursor.execute(...)`, `self.db.execute(...)`) whose **first positional argument is not a string literal** (dynamic SQL). A first argument that is a string literal is safe regardless of other arguments. |
| R2 | `CWE-78`  | A call to `os.system` or `os.popen` whose first positional argument is not a string literal; OR a call to any `subprocess.*` function with the keyword `shell=True` whose first positional argument is not a string literal. |
| R3 | `CWE-95`  | A call to the bare name `eval` or `exec` whose first positional argument is not a string literal. |
| R4 | `CWE-502` | A call to `pickle.load`, `pickle.loads`, `dill.load`, `dill.loads`, or `yaml.load` — regardless of arguments. |
| R5 | `CWE-327` | A call to `hashlib.md5` or `hashlib.sha1` — regardless of arguments. |
| R6 | `CWE-798` | An assignment (plain or annotated) whose single target is a plain name that, lowercased, contains `password`, `passwd`, `secret`, or `api_key`, and whose value is a non-empty string literal. |
| R7 | `CWE-601` | A call to a function named `redirect` (bare name or final attribute `redirect`) whose first positional argument is not a string literal. |
| R8 | `CWE-918` | A call to `requests.get` or `requests.post` whose URL argument (first positional argument, else the keyword `url=`) is not a string literal. |

Anything not covered by these rules is **safe** and must not be reported.
Known safe look-alikes include: parameterized `execute(sql, params)` where
`sql` is a literal; `subprocess.run([...], shell=False)` (list form, no
`shell=True`); `hashlib.sha256`; `json.load`; `eval`/`exec`/`os.system`/
`redirect` of a string literal; `pickle` never imported.

A component may earn multiple different CWEs (one entry each). The same CWE
from different rules applies once per component.

## Example

```python
API_KEY_STORE = "k-1299"          # -> {"component": "<module>", "cwe": "CWE-798"}

def lookup(uid):
    return db.execute("SELECT * FROM t WHERE id = " + uid)   # -> CWE-89

def lookup_ok(uid):
    return db.execute("SELECT * FROM t WHERE id = ?", (uid,))  # safe, no finding
```

Report for that fragment:
```json
{"findings": [{"component": "<module>", "cwe": "CWE-798"},
              {"component": "lookup", "cwe": "CWE-89"}]}
```

## Constraints

- Python 3 standard library only (`ast`, `json`, `sys`, ...). No third-party
  packages, no network at verify time.
- Do not modify `/app/report_service.py`.
- The verifier runs `/app/solve.py` unchanged on hidden source files
  (`module.py`) that follow the same rules — mixes of the catalog patterns and
  safe look-alikes, module-level code, classes with methods, and nested
  functions. Your analyzer must handle all of them.
