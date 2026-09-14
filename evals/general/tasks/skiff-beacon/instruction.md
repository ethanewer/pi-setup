# URL decoding corrupts literal `+` characters when plus-to-space conversion is disabled

## Situation

`/app/src` is a shallow, pinned clone of the **falcon** repository
(`https://github.com/falconry/falcon`), checked out in detached HEAD at
upstream commit `6566f4a4254fcc0158635c2e3bd4983663070ae4`. Everything the
project needs to run — including the Cython-compiled extension modules that
accelerate its URI handling — is already built in place in the checkout, so
the framework works with no setup step, fully offline. There is **no network**
at trial time: `git fetch`, `curl`, `pip install` and any other network use
will fail.

falcon is a Python library; you import it straight from the checkout:

```
cd /app/src && PYTHONPATH=/app/src python3 - <<'PY'
from falcon.util import uri
print(uri.decode('hello%20world'))
PY
```

`pytest` is installed and the project's own test suite runs offline:

```
cd /app/src && PYTHONPATH=/app/src python3 -m pytest tests/test_utils.py -q
```

The compiled extension is rebuilt from the tree's sources with a single
short command whenever a source file it depends on changes
(`cythonize` + `gcc`, a few seconds):

```
cd /app/src && python3 setup.py build_ext --inplace
```

Do not modify anything outside `/app/src` and `/app/repro.py`. `/opt/pristine`,
`/opt/golden`, `/tests` and `/solution` are harness-owned; do not read, write
or modify them.

## The bug

falcon's URI utilities decode percent-encoded characters (`%20` becomes a
space). The public function

```
falcon.util.uri.decode(encoded_uri, unquote_plus=True)
```

models `urllib.parse.unquote_plus`: by default a literal `+` is translated to
a space, mirroring how HTML forms encode spaces. Setting `unquote_plus=False`
disables that translation and is the documented way to decode parts of a URI
other than the query string, where `+` must be preserved as a literal plus.

In this checkout that documented behaviour is broken. With
`unquote_plus=False`, a literal `+` that happens to be followed by two
hexadecimal digits is misread as a percent-encoding escape and replaced by the
byte those two digits encode. For example, a common ISO-8601-style path
segment with a UTC offset,

```
'2026-06-29T23:11:38.964935+00:00.jpg'
```

decodes to `'2026-06-29T23:11:38.964935\x00:00.jpg'` — a NUL byte is injected
where the `+00` was. Any value carrying such a plus is silently corrupted:
timestamps with offsets like `+00:00`, `+05:30` or `+01:00`, filenames that
happen to contain `+0A` or `+F1`, and so on. With `unquote_plus=True` the
behaviour is correct, and the library's pure-Python fallback path is correct
too — only the accelerated compiled code path misbehaves.

`urllib.parse.unquote_plus` semantics are the spec: with `unquote_plus=False`,
`+` is a literal plus **no matter what follows it**; only an actual `%XX`
sequence is a percent escape.

## What you need to do

Produce two deliverables:

1. **`/app/repro.py`** — your own reproduction of the defect, written before
   you touch any source code. Requirements:
   - It must obtain falcon by ordinary import (`from falcon.util import uri`),
     resolved through `PYTHONPATH`. It must **not** hardcode any filesystem
     path (no `sys.path.insert`, no absolute paths): the verifier runs the
     very same script against two different falcon trees that differ only in
     the `PYTHONPATH` it sets, and the script must work in both runs.
   - It must assert the correct behaviour for the affected inputs, print every
     failing case with the actual and expected values, and exit non-zero while
     the defect is present and zero once the code is fixed.
   - Prove it in both directions yourself:
     at trial start `/app/src` still exhibits the defect, so
     `cd /tmp && PYTHONPATH=/app/src python3 /app/repro.py` must exit non-zero.
     After your fix the same command must exit zero.

2. **The repaired `/app/src` tree.** Change only what the fix requires — make
   the accelerated path behave exactly like the pure-Python path (and like
   `urllib.parse.unquote_plus`) for literal pluses. Do not rewrite history,
   fetch, commit, add or delete files, or change the test suite, build files,
   or anything else; keep the change minimal and in the spirit of the library.

After your fix, all of the following must hold (from within `/app/src`):

- `PYTHONPATH=/app/src python3 /app/repro.py` exits 0;
- `PYTHONPATH=/app/src python3 -m pytest tests/test_utils.py -q` is green;
- the timestamp segment above decodes to itself unchanged with
  `unquote_plus=False`.

## What the verifier checks

1. The tree is still the pinned checkout: `HEAD` equals
   `6566f4a4254fcc0158635c2e3bd4983663070ae4`, the history was not rewritten,
   and the only tracked file that differs from the pinned commit is the one
   source file the fix requires (plus build artifacts, which are untracked).
2. The extension is rebuilt from your repaired tree and the project's own
   regression test for this behaviour — extracted by the image from the fixing
   upstream commit into `/opt/golden` — passes when run against your tree.
3. The project's own test suite slice (`tests/test_utils.py`,
   `tests/test_query_params.py`, `tests/test_cython.py`) passes against your
   repaired tree, proving nothing else broke.
4. Your `/app/repro.py` is run against a pristine pre-fix checkout of the
   same commit: it must fail there, proving the reproduction genuinely detects
   the defect; and it must pass against your repaired tree.
5. Two authored hidden cases exercise the same decoding path with hex-digit
   combinations and UTC offsets the upstream regression does not use; all must
   pass against your repaired tree.

Deliverables: the repaired `/app/src` tree and `/app/repro.py`.