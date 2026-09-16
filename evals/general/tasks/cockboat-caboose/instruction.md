# A malformed Content-Type parameter crashes response encoding resolution

## Situation

`/app/src` is a shallow, pinned clone of the **requests** HTTP library
(`https://github.com/psf/requests`), checked out at upstream commit
`bc7dd0fc4d56e808bcdd85ac2d797b3107c89259`. The clone is detached at that
commit and contains exactly one commit -- nothing else. Python 3.12 with a
pinned set of dependencies is installed, and the project itself is installed
editable, so `import requests` resolves to `/app/src`. There is **no network**
at trial time: `pip`, `curl` and `git fetch` will not work; everything you need
is already in the image.

## The bug

When the library resolves a response's encoding from its `Content-Type`
header, a header parameter that has **no `=` and no value** breaks it.

Concretely, a server may send a header like:

```
Content-Type: text/html; charset
```

(many real-world servers send exactly this: a parameter named `charset` with
nothing after it). Resolving the response encoding from such a header crashes
with an `AttributeError`, instead of falling back to the default encoding for
text content, which must be `ISO-8859-1`. The same resolution runs for every
HTTP response the library produces, so a page served with such a header makes
ordinary request handling blow up.

The failure signature is:

```
AttributeError: 'bool' object has no attribute 'strip'
```

The header had no charset to extract, so the library must behave exactly as if
the malformed parameter were not there at all:

- `Content-Type: text/html; charset` must resolve like `Content-Type: text/html`
  (no parameters): encoding `ISO-8859-1`;
- `Content-Type: text/plain; charset` resolves like `Content-Type: text/plain`;
- well-formed parameters must keep working exactly as before
  (`Content-Type: text/html; charset=UTF-8` still resolves to `UTF-8`, quoted
  values are still unquoted, parameter keys are still lower-cased);
- all of the project's existing tests already pass at this commit and must
  continue to pass -- note that the existing suite does **not** cover a
  valueless parameter, which is precisely why this bug shipped.

## Deliverables

You must produce both of these:

1. **`/app/repro.py`** -- your own failing reproduction, which you write
   **first**, before changing any code. It is a single-file Python program,
   runnable as `python3 /app/repro.py` from any directory, that:

   - consults the library's own encoding-resolution machinery (the code path
     that turns a set of response headers into an encoding) with a headers
     mapping that contains the malformed Content-Type shown above;
   - prints the resolved encoding to stdout on a single line;
   - exits with status 0 if and only if the library behaves correctly -- i.e.
     it does not crash and the resolved encoding is the correct fallback
     `ISO-8859-1`;
   - exits non-zero when the bug is present in the library (in practice the
     `AttributeError` propagates and the script dies with it).

   Write it, run it while the bug is still present, and confirm it crashes.
   You keep the same file as your deliverable for the whole task; the verifier
   runs it twice at the end -- against the tree you leave in `/app/src` (it
   must print `ISO-8859-1` and exit 0) and against a pristine copy of the
   unmodified buggy tree that the image keeps at `/opt/prefix-src` (it must
   crash the same way). So your reproduction must genuinely exercise the
   library; a script that prints the string without doing the work will be
   caught by the second run.

2. **`/app/src`** -- the repaired tree. Fix the bug in the checkout so that
   the crash disappears and the resolution above returns `ISO-8859-1`, while
   every other behaviour is unchanged. The fix is small and lives in the
   implementation of the header parsing; nothing else in the project needs to
   change.

## How to work

Drive everything from `/app/src` with the project's own tooling. Useful
commands:

```
cd /app/src
python3 /app/repro.py              # must crash while the bug is present
python3 -m pytest tests/test_utils.py tests/test_structures.py \
    tests/test_help.py tests/test_packages.py tests/test_hooks.py
```

The working tree you leave behind is what gets judged:

- The clone must remain at the pinned commit `bc7dd0fc4d56e808bcdd85ac2d797b3107c89259`
  with exactly one commit. Do not fetch, do not commit, do not add refs or
  tags, do not move `HEAD`.
- Do not modify, add or delete any file that is not required for the fix --
  in particular do not touch build files, configuration files, the test suite
  (`tests/`), dependency pins or `.gitignore`, and do not leave scratch files
  or cache directories inside the repository. Put anything scratch outside the
  repo (e.g. `/tmp`).
- The single fix must be implemented in the repository source; the verifier
  checks that the only modified tracked file is the implementation of the
  affected header parsing, that no tracked file was deleted, and that no new
  files appeared.
- `/app/repro.py` lives **outside** the repository (it is at `/app`, the
  repository is `/app/src`).

Everything under `/opt`, `/tests` and `/solution` is harness-owned; do not
touch it. There is no network: `pip install` and `git fetch` will not help you.

## What the verifier checks

1. The tree is still at the pinned commit with exactly one commit, the fix is
   unreachable, no history was fetched, no tracked file was deleted, the only
   modified tracked file is the implementation of the header parsing (with at
   least one modification), and no untracked/config files were added.
2. `/app/repro.py` run against the repaired `/app/src` tree: exits 0 and
   prints `ISO-8859-1`.
3. `/app/repro.py` run against the pristine pre-fix tree image copy: exits
   non-zero with the `AttributeError ... 'strip'` signature.
4. The project's own regression test for this behaviour (kept out of the tree
   at `/opt/golden/` and copied in by the verifier) passes.
5. The project's own existing tests around the affected code still pass.
6. Hidden cases over valueless/valued parameter combinations that the upstream
   test does not use pass.

Deliverables: the repaired `/app/src` tree and `/app/repro.py`.