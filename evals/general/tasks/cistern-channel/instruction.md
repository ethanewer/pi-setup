# cistern-channel

You are working inside a real upstream open-source library: **falconry/falcon**,
a Python web framework, checked out at a pinned commit in `/app/src` (the
working tree starts clean). There is a bug in this tree's multipart upload
parsing configuration. Your job is to find it, fix it in the working tree, and
prove the fix with the project's own test tooling. You are deliberately
**not** told which file or function to change: localising the bug is part of
the task.

## Environment

- Python 3.12 with `pytest` installed (everything needed is already on the
  image). `falcon` is installed **editable** from `/app/src`, so your changes
  to the tree take effect on the next `import falcon`. `PYTHONPATH=/app/src`
  is also set.
- Outbound network is **not available** and must not be relied on. There is
  nothing to download: the project is pure Python with zero runtime
  dependencies.
- `cpus = 1`: one vCPU.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

Multipart (file-upload) forms are parsed with a per-parser configuration
object; among the configurable settings is the dict-like
`media_handlers` mapping — the set of media types (e.g. `application/json`,
`application/x-www-form-urlencoded`) that the parser knows how to deserialize
the various upload parts with. Applications customise this mapping, for
example to remove a built-in handler or to add a handler for a custom
content type.

The bug: customising `media_handlers` on **one** multipart parser silently
leaks into **every other** multipart parser created in the same process.
Removing or replacing a handler on one upload parser removes or replaces it
for all others, so unrelated requests suddenly fail to parse or render their
upload parts with the wrong serializer. Configuration mutations should be
isolated per parser instance.

Reproduce it in the interpreter:

```
python3 - <<'PY'
import falcon
from falcon.media import MultipartFormHandler
a = MultipartFormHandler().parse_options
b = MultipartFormHandler().parse_options
a.media_handlers.pop(falcon.MEDIA_JSON)
print('a:', len(a.media_handlers), 'b:', len(b.media_handlers))
print('shared:', a.media_handlers is b.media_handlers)
PY
```

On this tree it prints `a: 1 b: 1` and `shared: True`: handing JSON handler
removal off the first parser also took it away from the second. After a
correct fix it must print `a: 1 b: 2` and `shared: False` — the second
parser keeps both default handlers, and its choices stay its own.

## Requirements

1. Fix the tree so that customising the media handlers of **one** multipart
   parser never affects any other parser created in the same process: each
   parser must start from the framework's default handler set as its **own**
   instance, and mutations (removing, replacing or adding handlers) must stay
   scoped to the parser that made them.
2. Everything else must keep working exactly as before: a parser whose
   handlers were customised must still behave per its own configuration, and
   the default handler set (the two built-ins `application/json` and
   `application/x-www-form-urlencoded`) must remain intact for every new
   parser, no matter what other parsers have done.
3. The graded tree must be byte-identical to the original except for the
   source file(s) where the bug lives. Do not add, move, delete, rename or
   reformat any file; if you create scratch files to investigate, delete them
   before you finish; make no commits. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above (it goes through the documented
   `MultipartFormHandler.parse_options` API, which is how real applications
   reach this configuration).
2. **Localise** the bug in the source (the parser configuration lives under
   `falcon/media/`; read the class that owns `media_handlers` and follow how
   an instance's `media_handlers` is initialised). Apply a minimal fix and
   re-run the reproduction.
3. **Verify** with the project's own test suite slice:
   `cd /app/src && python3 -m pytest tests/test_media_multipart.py tests/test_media_handlers.py tests/test_media_urlencoded.py tests/test_mediatypes.py -q`
   — everything must pass, plus your reproduction must now show isolated
   behaviour.
4. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the source file(s) the bug lives in is byte-identical
  to that commit (any other modification, added file or untracked scratch
  file fails);
- assert the installed `falcon` imports from `/app/src` (your tree, not a
  stale copy);
- require `/app/summary.md` to exist;
- place the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, from a successor revision of the tree) and its own
  hidden variants into the test tree, run `pytest` on the media suite slice
  above, and require every test — the regression test, the hidden variants,
  and all pre-existing tests — to run and pass.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.