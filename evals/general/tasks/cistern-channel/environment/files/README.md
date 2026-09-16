# cistern-channel — working environment

You are inside the real **falconry/falcon** Python web framework, checked out
at a pinned commit in `/app/src` (working tree starts clean, git history is a
single shallow commit, HEAD is detached — do not commit, fetch or rewind).

## Environment

- Python 3.12 with `pytest` installed. `falcon` is installed **editable** from
  `/app/src`, so any change you make to the tree is live on the next
  `import falcon`; `PYTHONPATH=/app/src` is set as a belt-and-braces fallback.
- Outbound network is **not available** at trial time and must not be
  relied on. Everything needed is already baked into the image. `pip install`
  or `git fetch` will fail — do not attempt them.
- `cpus = 1`: one vCPU. There is nothing to parallelise here; the test suite
  slice the grader runs finishes in well under a minute.
- Multipart form parsing and its per-parser configuration live under
  `falcon/media/` — but you are not told exactly where the bug is; finding
  it is part of the task.

## Working loop (recommended)

1. **Reproduce.** The interactive one-liner below demonstrates the symptom.
   Build your own minimal reproduction on top of it (e.g. through the
   documented `MultipartFormHandler.parse_options` API) and confirm the
   failure first.
2. **Localise.** Read the parser configuration code and find where one
   parser's settings can touch another parser's. A small, surgical change is
   enough; the grader allows changes in the two source files the bug's root
   cause lives in, and nowhere else.
3. **Verify.** Re-run your reproduction (must now print the isolated
   behaviour) and run the media test suite slice the grader uses:
   `python3 -m pytest tests/test_media_multipart.py tests/test_media_handlers.py tests/test_media_urlencoded.py tests/test_mediatypes.py -q`
   — it must stay fully green apart from whatever your bug caused.
4. **Write `/app/summary.md`** — a few lines on what the bug was, what you
   changed, and how you verified it.

## Requirements

1. Fix the tree so that customising the media handlers of **one** multipart
   parser never affects any other parser created in the same process.
2. Everything else must keep working exactly as before.
3. The graded tree must be byte-identical to the pinned commit except for the
   source file(s) where the bug lives. Do not add, move, delete, rename or
   reformat any file; delete scratch files you created; make no commits; do
   not touch `.git`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up.

## Grading

The verifier will, on your final tree:

- assert `HEAD` is still the pinned commit, that every tracked file except
  the bug's source file(s) is byte-identical to it (a content check, so
  assume-unchanged tricks cannot hide a dirty file), that no untracked
  non-ignored file remains, and that the installed `falcon` imports from
  `/app/src`;
- require `/app/summary.md`;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, from a successor revision of the tree) plus its own
  hidden variants, and run them together with the media suite slice above.
  Every listed test must run and pass, and every other test in the slice must
  stay green.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.