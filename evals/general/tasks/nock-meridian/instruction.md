# pip stores a corrupted local file name for URLs with double-encoded names

## Environment

- A development checkout of the **pip** source tree is at **`/app/src`**, at
  the exact revision this task was measured against. pip uses a nested `src`
  layout, so the package itself is under `/app/src/src`.
- The container has **no network**. Do not try to `pip install`, `git fetch`
  or download anything; every dependency the project's test suite needs is
  already installed (pytest, pytest-socket, installer, scripttest,
  virtualenv, werkzeug).
- To drive the checkout's own code instead of the pip installed in the base
  image (so edits you make under `/app/src` take effect immediately):

  ```bash
  cd /app/src && PYTHONPATH=src python3 -c "import pip; print(pip.__file__)"
  ```

  and to run the project's own unit tests:

  ```bash
  cd /app/src && PYTHONPATH=src python3 -m pytest -q -o addopts= -p no:cacheprovider tests/unit/... -q
  ```

  Focused unit tests run in seconds. The machine is budgeted at one CPU;
  everything here is pure Python.

- The checkout is a git repository at the pinned revision with a clean tree.
  `git status` / `git log` inside `/app/src` are yours to use. Keep scratch
  files under `/tmp`, never inside the repository.

## The bug

When pip downloads a file (from a package index, a direct URL, or a
`--find-links` page) it works out a **local file name** for the URL on the
local disk. That name is what pip stores in `--download` directories, what
it later looks up before re-downloading, and what it records for a
subsequent build or install.

For some URLs, the file name pip derives is not the file name the URL
actually names. If the URL's path contains a percent-encoded byte that is
itself the encoding of a character (a *doubly encoded* byte — for example a
URL that must be decoded once to recover a literal `%2F`, i.e. the raw URL
contains `%252F`), then the derived local file name contains the *decoded*
character instead of the literal escape. In particular, a URL like

```
https://example.com/a%252Fb.whl
```

is a URL for a single file whose real name is the literal string
`a%2Fb.whl` — the `%2F` is part of the file name, not a path separator.
But pip's derived name for it is `a/b.whl`: the two characters `%2F` have
been decoded into a real `/`. The derived name is no longer a single file
name at all — it is a relative path with a directory component that does
not exist in the URL. The same corruption hits other encoded characters
(`%2520` becomes a real space, `%252B` becomes `+`, `%252e` becomes `.`),
and for names like `%252e%252e%252f...` the derived value even contains
`..` path components.

The result is that pip's download, cache and build paths all refer to a
different file than the one the URL names: the written/read-back file path
is wrong, and in the separator case it points through directories that were
never part of the URL. Users hit this with per-user indices and local
servers that double-encode characters in their artifact file names.

The behaviour you must preserve: for an *ordinarily* encoded name (decoded
exactly once), the derived name is unchanged — `page%231.html` still
derives the name `page#1.html`, and `myproject-1.0%2Bfoobar.whl` still
derives `myproject-1.0+foobar.whl`.

## What you must deliver

1. **`/app/reproduce.py` — your own failing reproduction, as a deliverable.
   Write this first, before touching any pip source.** A single-file Python
   script that:

   - takes the path to the pip checkout as its first command-line argument
     (default `/app/src`);
   - builds a concrete URL of your choosing whose derived file name, under a
     *correct* pip, is a single path component containing a literal
     percent-escape (pick a URL with a doubly encoded byte — that is the
     point of this bug);
   - derives the local file name for that URL **using the checkout's own
     pip code** — the model class pip uses to turn an install URL into a
     local file name — importing it from the checkout given on the command
     line, never from site-packages;
   - prints exactly one line to stdout: `FILENAME: <derived name>`;
   - exits **0 if and only if** the derived name is a single path component
     (contains no `/` and equals its own basename), and **1 otherwise**
     (including when deriving the name raises an exception).

   It will be run as `python3 /app/reproduce.py /app/src` against your
   repaired tree, and again against a pristine, unmodified copy of the
   original checkout. On the pristine buggy tree your script must FAIL (exit
   1, printing the corrupted name); on the repaired tree it must PASS (exit
   0). Verify both directions yourself before you consider yourself done.
   The script must be self-contained: it may use only the Python standard
   library plus the checkout's own source (the runner isolates it from
   site-packages and from any interpreter startup hooks).

2. **A fixed pip.** Make the checkout's own code derive the correct name:
   the derived file name must be the once-decoded file name of the URL —
   always a single path component, never containing a separator that was
   not in the URL, and never `""`, `.` or `..`. Wherever pip joins that
   name onto a download directory, the join must stay inside that directory.

   Only pip source files under `/app/src/src` may be modified. Do not add,
   rename or delete any other tracked or untracked file in the repository,
   do not change the checked-out revision, and do not touch anything outside
   `/app/src` (no site-packages, no interpreter, no wrappers).

The acceptance will then:

1. run **your** `/app/reproduce.py` against the repaired tree (must pass)
   and against a pristine copy of the original checkout (must fail, showing
   the corrupted name);
2. run the project's own updated regression tests for this behaviour
   (baked into the image at `/opt/golden`) against your tree — they must
   pass;
3. run a slice of the project's own existing unit test suite that covers
   the same code area — it must still pass;
4. run a set of additional inputs your reproduction does not cover — they
   must all behave correctly.

Where precisely the derivation happens, which source file(s) own it, and
how the double-decode is stopped is **your call** — the source tree, the
test suite and the git history inside `/app/src` are all there for you to
inspect. Write the reproduction first, watch it fail, then fix the code
until it passes.

## Deliverable summary

- `/app/reproduce.py` — your own failing reproduction (see contract above).
- A fixed `/app/src` — the pip checkout, repaired in place.
- Nothing else. No report file, no new scripts anywhere under `/app/src`.