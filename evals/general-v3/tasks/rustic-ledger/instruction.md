# Audit a content-addressed object store

`/app/store` is a miniature content-addressed object store: a small git-like
graph of blobs, trees, and commits. The data format is documented in
`/app/FORMAT.md`. Read that file first.

You must write a reusable CLI program, `/app/audit.py`, that audits **any**
such store and reports three things:

- the set of **reachable** object IDs reachable from `refs/HEAD`,
- the set of **unreachable** object IDs (valid objects present but not reachable),
- the set of **secrets** (reachable ids of blobs whose text contains a
  credential-looking string).

The verifier runs your program on hidden stores it does not show you, so your
program must be generic: it must work on any store directory that follows the
documented layout, not just this one.

## Program contract (exact)

Invoke your program as:

```
python3 /app/audit.py <store_dir> <output_json>
```

- `<store_dir>` may be `/app/store` or any other store directory.
- Write the report to `<output_json>` (create parent directories as needed) as a
  JSON object with exactly three keys, each a sorted list of unique object IDs:

  ```json
  {"reachable": [...], "secrets": [...], "unreachable": [...]}
  ```

- Object IDs are the SHA-256 hex digests used as object filenames.
- Your program must be deterministic (no network), must exit 0 on success, and
  must not modify or delete anything under `<store_dir>`.

## Rules you must implement

**Verify the self-hash.** An object is addressable only when its stored
filename equals the SHA-256 hex digest of its canonical JSON payload:

```python
json.dumps(obj, sort_keys=True, separators=(',', ':')).encode('utf-8')
```

Recompute the digest from the decoded payload bytes — never trust any annotation
in the object. A file that fails to parse as JSON, or whose filename does not
match its digest, is **ignored entirely**: it is neither reachable nor listed as
an unreachable candidate.

**Reachability.** Start at the trimmed contents of `refs/HEAD`. For a
`commit`, follow its `tree` and (when present, a string) its `parent`. For a
`tree`, follow every string in its `blobs` array. Every ID visited this way is
reachable. `unreachable` = all addressable object IDs minus the reachable ones.

**Secrets.** A secret is a **reachable** object of type `blob`
whose `text` contains a credential-looking string (case-insensitive):

```
AKIA[0-9A-Z]{16}
| -----BEGIN [A-Z ]*PRIVATE KEY-----
| (password|passwd|secret|token|apikey|api[_-]?key|access[_-]?key) [:=] <non-empty token>
```

The keyword form must be a key from that list followed by a colon or `=` and a
non-empty token (whitespace allowed around the separator). A credential-looking
string in an **unreachable** blob must NOT be reported; report only reachable
blob IDs in `secrets`.

## Edge cases the hidden verifier probes

- A chain of commits where the head is the newest; older commits and the objects
  they point at are still reachable.
- A credential-looking string inside an **unreachable** blob (must not appear in
  `secrets`; the object still appears only in `unreachable`).
- A missing or empty `refs/HEAD` file: nothing is reachable, every addressable
  object is unreachable.
- A dangling head (an ID not present in the object set): nothing is reachable.
- Corrupt (unparseable) object files and objects stored under a mismatched
  filename: excluded entirely.
- Objects with `parent` absent, `null`, or a non-string value must not crash.

## Do NOT modify

Do not create, delete, or modify anything under `/app/store`. Your program must
only read the store and write its report to another location.

## Deliverables

1. `/app/audit.py` — the reusable CLI program described above.
2. `/app/audit.json` — its output when run on the shipped store:

   ```
   python3 /app/audit.py /app/store /app/audit.json
   ```

`/app/audit.json` is a sanity-check output; the verifier additionally runs your
program on hidden stores.