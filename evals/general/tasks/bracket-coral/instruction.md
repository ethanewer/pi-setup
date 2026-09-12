# Multipart file uploads must round-trip byte-for-byte

## Situation

`/app/src` is a pinned, shallow clone of the Werkzeug WSGI library
(`https://github.com/pallets/werkzeug`) checked out at one specific upstream
commit from August 2023, and installed from that tree in editable mode, so the
code you import is exactly the checked-out Python source. Python 3.12 and
pytest are installed. There is **no network** at trial time: everything you
need is already in the image; `pip` and `git` fetches will not work.

Werkzeug parses `multipart/form-data` uploads (the format browsers use for
`<input type=file>`) with a streaming multipart decoder. A WSGI server feeds
the raw request body into the
decoder in whatever chunks arrive from the socket; the decoder emits one event
per part, first the part headers, then `Data` events with the uploaded file
bytes, then a final event for the closing boundary. `parse_form_data` in
`werkzeug.formparser` runs this pipeline and hands you the uploaded file
through `FileStorage`, so any corruption in the decoder shows up as a file on
disk that differs from what the client sent.

## The bug

For an upload whose file content ends with newline bytes right where the
part's closing boundary begins, the decoder does **not** return the uploaded
bytes exactly: carriage-return/line-feed bytes that belong around the part
boundary get mixed into the file content. For example, driving the decoder
directly (see `/app/probe_upload_corruption.py`):

- uploading `b"x\ry"` comes back as `b"\nx\ry"` (an extra `\n` prepended),
- uploading `b"\n\n"` comes back as `b"\r\n\n\n"`,
- uploading `b"\r\nX\r\n"` comes back as `b"\r\n\r\nX\r\n"`,

so a client that sent a file whose content is `x<CR>y` gets a stored file with
an extra leading line feed. Uploads whose content does **not** end in a line
break round-trip fine, which is why the corruption is easy to miss.

Reproduce it right now:

```
python3 /app/probe_upload_corruption.py
```

It prints the received bytes for several uploads and exits non-zero because
four of them are corrupted. The same bug is visible through the project's own
form parser when the body reaches the decoder in several chunks.

## What the fix must satisfy

Make the multipart decoder return the uploaded file bytes **exactly**, in
every layout:

1. Every file part's `Data` events must reassemble, byte-for-byte, the file
   bytes that were uploaded — no trailing `\r`, `\n` or `\r\n` bytes from the
   part boundary may leak into the file, and no file bytes may be dropped,
   regardless of where the decoder's internal buffer happens to cut between
   the file content and the closing boundary.
2. This must hold for uploads whose content ends in LF, CR, CRLF or blank
   lines, for uploads that do **not** end in a line break, and for binary
   content, whether the whole body arrives in one chunk or in several.
3. Uploads whose content does not end in a line break must keep round-tripping
   exactly as they do today.

Drive your work with the project's own test runner, from `/app/src`
(`/app/run_tests.sh` runs the multipart-adjacent slice; the tree's own tests
pass at the pinned commit — keep them that way):

```
cd /app/src && python3 -m pytest tests/sansio/test_multipart.py -q -p no:cacheprovider
```

Add your own scratch tests if they help you verify (then delete them again),
but the verdict on your fix is made by the verifier, which runs the project's
own regression test for this bug plus hidden cases of its own.

## Constraints

- The clone at `/app/src` is the deliverable: change only the minimal
  production code the fix requires, in place. Do not add, remove or rename any
  tracked file, do not add new files under `src/werkzeug/`, do not touch
  anything under `.git`, and do not fetch.
- `/opt/golden`, `/tests` and `/solution` are harness-owned — do not read or
  modify them.
- No network; everything you need is already installed.

## What the verifier checks

1. Tree provenance: still at the pinned upstream commit, no fetched commits,
   and no tracked file outside the minimal production source changed.
2. The project's own regression test for this bug — extracted from the
   upstream fix revision at image-build time into the harness-owned
   `/opt/golden` — passes against your tree.
3. The tree's own multipart, form-parser and request-wrapper test files still
   pass.
4. Hidden cases over inputs the upstream regression test does not use: chunked
   low-level decoding with different boundaries and file bytes, and an
   end-to-end upload parsed through the project's own form parser with a small
   read buffer.

Deliverable: the repaired `/app/src` tree.