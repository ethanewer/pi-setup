# hazel-quill — decode the quarantine filenames

The mail gateway dropped a batch of attachments into a quarantine mailbox at
`/app/quarantine/`. To defuse attachment tricks, the gateway rewrote every
stored file's name: the original filename was encoded with **standard base64**
(RFC 4648, with `=` padding) and stored as `<BASE64>.qtn`. Some stray junk
landed in the quarantine too.

## Deliverable

Write one reusable program, `/app/unquarantine.py`, invoked as:

```
python3 /app/unquarantine.py <input_dir> <output_dir>
```

It must work on **any** quarantine directory following the scheme below, not
just the shipped one — the verifier re-runs it on hidden directories.

## Naming scheme (exact)

1. Consider only **regular files directly inside** `<input_dir>` (no
   recursion, no symlinks) whose name ends with the literal suffix `.qtn`.
2. The candidate segment is the filename minus the `.qtn` suffix.
3. Decode the segment with **standard base64** and **strict validation**
   (`base64.b64decode(segment, validate=True)` semantics): the segment must be
   non-empty, use only the alphabet `A-Za-z0-9+/=`, have a length that is a
   multiple of 4, and carry correct padding. Anything else is invalid.
4. The decoded bytes must decode as UTF-8 to an **original filename** that is
   safe to restore: non-empty, contains no `/` and no NUL byte, and is neither
   `.` nor `..`. Otherwise the file is invalid.
5. Every file failing any step above is a **decoy**: skip it silently, keep
   processing the rest, and never crash.

## Behavior on success

For every valid file:

- copy its **bytes, unchanged**, to `<output_dir>/restored/<original filename>`
  (creating parent directories as needed — note the original filename itself
  never contains `/`),
- record the original filename in the manifest.

Then write `<output_dir>/recovered.txt`: the manifest — one original filename
per line, in **ascending string sort order** (plain Python `sorted()`), with a
final newline. If there are no valid files, `recovered.txt` is empty.
Distinct valid files always map to distinct original names in the supplied
quarantines; if a collision ever occurs, the last processed file (ascending
filename order) wins and the name is listed once.

The program must exit `0` in all cases (even when every file is a decoy).

## Visible run

Run it on the shipped quarantine so the artifacts land in `/app`:

```
python3 /app/unquarantine.py /app/quarantine /app
```

This must leave `/app/recovered.txt` and `/app/restored/` in place.

**Do not modify anything inside `/app/quarantine/`** — the files are checked
byte-for-byte afterwards.

## Hidden cases

The verifier re-runs the program on hidden quarantine directories with
different original names and different decoys (bad base64 alphabet, wrong
length/padding, decoded names containing `/`, non-UTF-8 decodes, files without
the `.qtn` suffix, an empty `.qtn` name) and checks the manifest, the restore
byte-equality, and the exit status of each run.

## Constraints

- Python 3.12 standard library only; no network at verify time.
- The verifier executes `/app/unquarantine.py` unchanged, so do not hard-code
  the shipped quarantine's contents.
