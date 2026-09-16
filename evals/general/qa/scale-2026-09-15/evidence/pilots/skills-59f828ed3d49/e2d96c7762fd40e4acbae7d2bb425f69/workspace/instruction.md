# Filesystem manifest auditor

Implement `/app/manifest_audit.py`, a standalone Python 3.12 command-line
program using Click 8.1.8. It must run without network access. Do not add
dependencies beyond Click and the Python standard library.

The program must expose a Click group with an `audit` subcommand:

```text
python /app/manifest_audit.py audit [OPTIONS] MANIFEST
```

Options:

* `--root PATH` selects the filesystem root and defaults to `.`. It must be an
  existing directory.
* `--policy PATH` optionally supplies a policy JSON file.
* `--format [json|text]` defaults to `json`.
* `--output PATH` defaults to `-`. `-` means stdout; any other path receives
  the report. Diagnostics must go to stderr.

The manifest is a JSON object with exactly one key, `files`, whose value is a
list. Each item is an object with exactly these keys:

```json
{"path": "src/main.py", "bytes": 12, "sha256": "64 lowercase hex characters"}
```

`bytes` is a non-negative integer. A path is a canonical relative POSIX path:
it is non-empty, uses `/`, does not begin with `/`, contains no `.` or `..`
components, and has no repeated separators. Reject NULs, backslashes, absolute
paths, traversal, duplicate paths, and symlink-resolved paths outside the
resolved root. Only regular files are auditable. A missing file, directory,
special file, symlink escape, byte-count mismatch, or digest mismatch is an
error; do not follow an escaping symlink. Hash the bytes actually read from the
file with SHA-256.

If present, the policy is an object with only these optional keys:

* `allowed_extensions`: list of non-empty strings such as `.py` or `.toml`;
* `max_bytes`: non-negative integer applying to every audited file;
* `required_paths`: list of canonical relative paths that must occur in the
  manifest;
* `forbidden_paths`: list of canonical relative paths that must not occur.

Reject malformed policy values, duplicate policy paths, and unknown policy
keys. A file outside `allowed_extensions`, over `max_bytes`, a missing required
path, or a forbidden manifest path is an error. Policy errors must be visible
in the report.

On every validly invoked audit, emit one report. The JSON report must be an
object with exactly `ok`, `checked`, and `errors` keys. `checked` is the number
of manifest records examined. `ok` is true only when `errors` is empty. Each
error is an object with exactly `path`, `code`, and `detail` string keys. Sort
errors by `(path, code, detail)` and serialize JSON with two-space indentation
and a final newline. Use stable error codes (for example `INVALID_MANIFEST`,
`DUPLICATE_PATH`, `PATH_TRAVERSAL`, `SYMLINK_ESCAPE`, `MISSING_FILE`,
`NOT_REGULAR`, `BYTE_MISMATCH`, `HASH_MISMATCH`, `EXTENSION_FORBIDDEN`,
`SIZE_LIMIT`, `REQUIRED_MISSING`, and `PATH_FORBIDDEN`); hidden tests inspect
the relevant codes, not incidental wording.

For `--format text`, emit the same result as deterministic plain text: first
line `OK` or `FAIL`, second line `checked: N`, then one line per error in sorted
order as `path: CODE detail`. An empty-error successful report has no further
lines. Exit 0 for `ok`; exit 2 when the report is not ok. Click usage errors
may use Click's normal nonzero exit. If `--output` resolves to the manifest,
policy, or an audited input, fail safely rather than overwriting it. Do not
print a report twice or mix report bytes into stderr.

The evaluator supplies temporary files and invokes both stdout and file output
modes. Keep behavior deterministic across runs and do not rely on the current
working directory beyond the documented default root.
