# httpx text streaming must not produce a trailing empty piece

## Situation

`/app/src` is a shallow, pinned clone of the httpx project
(`https://github.com/encode/httpx`), checked out at upstream commit
`90538a3b4610ba49ce16c997bcfdb9101f9503be`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
Python source. Python 3.12, pytest, and the dependencies the project's own test
suite needs (including `chardet==5.2.0`, which `tests/test_decoders.py` imports
at module scope) are installed. There is **no network** at trial time:
everything you need is already in the image; `pip` and `git fetch` will not work.

## The bug

When an HTTP response body is delivered as a stream (multiple chunks, as a real
transport would), iterating over its decoded text yields a **spurious empty
string after all the real content**. Code that iterates `response.iter_text()`
over a streamed body receives one extra empty piece at the end that is not part
of the response. As a result:

- a chunk list that should be `["Hello,", " world!"]` comes back as
  `["Hello,", " world!", ""]`;
- a document rebuilt with `"".join(response.iter_text())` ends up with a
  trailing empty element after it has been split back into chunks;
- code that asserts on the exact sequence of yielded chunks fails, because of
  the phantom empty chunk.

The body itself is fine: the bytes are intact, `response.content` decodes
correctly, and the same text iterated via a single-piece non-streamed body
looks right when joined. The defect is only in the *streamed* text-iteration
path.

## Reproducing the failure

```
python3 /app/probe_iter_text.py
```

At the pinned commit this prints the observed chunk list and exits non-zero,
reporting the spurious trailing empty string. Re-run it after your fix: it must
exit 0.

A one-liner that shows the same thing:

```
python3 -c "import httpx; print(list(httpx.Response(200, content=iter((b'Hello,', b' world!'))).iter_text()))"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that streaming the decoded
text of a response yields exactly the text of the body, chunk by chunk, and
**never a trailing (or interior) empty piece**. The exact list of chunks
produced by `iter_text()` over any streamed body must contain every piece of
the real text and nothing else, and `"".join(list(response.iter_text()))` must
be byte-identical to the correctly decoded body text. The same must hold for
the asynchronous `aiter_text()` path. Do not change what single-piece
(non-streaming) responses produce, and do not change the fixed-size chunking
behaviour of `iter_text(chunk_size=...)` for real content.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_decoders.py -q -p no:cacheprovider
```

The whole existing decoder test file is green at the pinned commit; keep it
that way. Add your own tests if that helps you verify (for example streamed
bodies with UTF-8 characters split across chunk boundaries, empty body chunks
inside the stream, or the async `aiter_text` path), but the verdict on your fix
is made by the verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch
  them.
- The verifier also asserts that the working tree remains at the pinned commit,
  that no other tracked files were modified, and that no new files were added
  inside the `httpx` package.

## What the verifier checks

1. The tree is still at commit `90538a3b4610ba49ce16c997bcfdb9101f9503be`, no
   extra tracked files were changed, and the repair touches only the minimal
   source surface.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing decoder suite (`tests/test_decoders.py`) and the
   `iter_text`/`iter_lines` response tests still pass.
4. Hidden cases over inputs the upstream test does not use pass, including
   UTF-8 characters split across chunk boundaries, empty chunks inside the
   stream, and the asynchronous `aiter_text` path.

Deliverable: the repaired `/app/src` tree.