# ballast-reach

You are working inside a real, large open-source codebase: **pypa/setuptools**,
the Python packaging build backend. It is checked out at a pinned commit in
`/app/src` (the working tree starts clean). There is a bug in the machinery
that interprets a project's `MANIFEST.in` — the file that decides which files
(`include`/`exclude`, `global-include`/`global-exclude`, `recursive-include`/
`recursive-exclude`, `graft`, `prune`) end up inside a built source
distribution. Your job is to find the bug, fix it in the working tree, and
prove the fix with the project's own test suite. The snippets below reproduce
the symptom through the MANIFEST.in matching machinery, but they do not tell
you where the byte-for-byte comparison goes wrong or which file to change:
localising the bug and choosing the fix is part of the task.

## Environment

- Python 3.12.13 and git 2.47.3. The project is installed **editable**
  (`pip install -e '.[test]'`), so `import setuptools` resolves to
  `/app/src/setuptools` and an edit you make in the tree is live for the next
  Python process. `coverage` is installed (the project's `pytest.ini`
  references that module in a warning filter).
- Pytest is pinned to **8.4.2** in this image and must stay that way: the
  repository's own `pytest.ini` turns warnings into errors, and any other
  pytest version breaks test collection in this tree.
- **There is no network** in this container, and none is needed: all of the
  project's test dependencies are already installed and its test suite is
  self-contained.
- `cpus = 1`: one vCPU. Do not launch parallel test runs.
- Scratch files and whole test projects you create to experiment belong in
  `/tmp`, never in `/app/src`. One exception: `setuptools.egg-info/` already
  sits in `/app/src` from the install step — leave it alone.
- Do not run `git add`, `git commit`, `git fetch`, `git checkout`, `git
  reset`, `git rebase`, `git clean` or any other write against `/app/src/.git`,
  and do not edit files under it. The grader asserts the working tree's
  provenance (see Grading).
- Bytecode and pytest cache are redirected to `/tmp` in this image, so test
  runs leave nothing behind in the tree.

## The bug (user-visible symptom)

A project author writes `MANIFEST.in` rules that *exclude* files from the
source distribution:

```
global-include *.txt
global-exclude café.txt
```

Some filesystems (macOS APFS/HFS+, in particular) store most file names in
**decomposed** Unicode form ("NFD"): `café.txt` is stored as `cafe` + a
combining acute accent, whereas editors author text in **composed** form
("NFC"), one code point `é`. The two spellings are visually identical but
byte-for-byte different.

When the on-disk name of a non-ASCII-named file differs from the rule's text
only in normalization form, the exclusion **silently fails**: the file still
ships inside the built `sdist` even though the author explicitly excluded it —
a data-leak-grade packaging defect. The same leak affects `exclude`,
`global-exclude`, `recursive-exclude` and `prune`, because all of them compare
the rule's text against candidate paths byte-for-byte.

## Reproduce it

```bash
python3 - <<'PY'
import unicodedata
from setuptools.command.egg_info import translate_pattern
nfc = unicodedata.normalize('NFC', 'café.txt')   # composed
nfd = unicodedata.normalize('NFD', 'café.txt')   # decomposed
assert nfc != nfd
m = translate_pattern(nfc).match(nfd)
print('MATCH:', m is not None)
assert m is not None
PY
```

On this tree this prints `MATCH: False` and the assertion fails: the same file
name, differing only by normalization form, is not matched. After a correct
fix it must print `MATCH: True`.

And through the project's own `FileList` class — the mechanism behind every
`MANIFEST.in` action — where the leak becomes visible:

```bash
python3 - <<'PY'
import unicodedata
from setuptools.command.egg_info import FileList
nfc = unicodedata.normalize('NFC', 'café.txt')
nfd = unicodedata.normalize('NFD', 'café.txt')
fl = FileList()
fl.files = [nfd]              # file present in the manifest under its
                              # decomposed on-disk name ...
fl.global_exclude(nfc)        # ... excluded with the composed form
assert nfd not in fl.files, 'excluded file is still in the file list'
print('excluded')
PY
```

On this tree the assertion fails: the excluded file stays in the list.

## Requirements

1. **Fix the mechanism, not the sample.** Make the matching of `MANIFEST.in`
   rule patterns against candidate paths insensitive to Unicode normalization
   form, in **both directions**: a rule authored composed must match a name
   stored decomposed, and a rule authored decomposed must match a name stored
   composed. Names that are genuinely different must of course continue to
   **not** match. The fix must cover all four exclusion kinds listed above
   (they all route through the same matching primitive) as well as the direct
   `translate_pattern(...).match(...)` contract.
2. **Only the matching code may change.** The graded tree must remain
   byte-identical to the pinned commit except for: the single existing module
   inside `setuptools/` that implements this pattern matching, and — if you
   choose to introduce one — one new helper module inside `setuptools/`
   implementing the normalization primitive you use. Do not add, move, delete,
   rename or reformat any other file; do not modify `tests/`, metadata files or
   configuration; make no commits; delete any scratch files you created inside
   the tree before finishing. The grader compares every file's bytes against
   the pinned commit's own blobs, so cosmetic side-changes also fail.
3. **The project's own tests must stay green.** `setuptools/tests/test_manifest.py`
   is the project's test file for this machinery, and it must keep passing:
   `python3 -m pytest -q setuptools/tests/test_manifest.py` (all tests in this
   file pass on the pristine tree and must keep passing after your change).
4. Write `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Deliverables

1. `/app/src` — the repository with your fix applied **in the working tree**
   (no commits).
2. `/app/summary.md` — the write-up.

## Working loop (recommended)

1. **Reproduce** with the two snippets above; keep all scratch data in `/tmp`.
2. **Localise**: find the matching primitive that all four exclusion kinds
   route through; read it; work out *why* a byte-exact regular expression
   misses when the rule and the on-disk name are different normalization forms
   of the same text.
3. **Fix** and re-run the reproduction — you must get `MATCH: True` and
   `excluded`.
4. **Prove nothing else broke**: keep `setuptools/tests/test_manifest.py`
   fully green with the command above.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned commit and that every file except
  the matching module (and the optional new helper module) is byte-identical
  to that commit, with no stray untracked files (generated artifacts like
  `*.egg-info/`, `__pycache__/` and `.pytest_cache/` are tolerated);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression tests** for this bug — upstream added
  them to `setuptools/tests/test_manifest.py` with the fix, so they do not
  exist in this tree; they are baked into the image — and run that whole test
  file, which must pass entirely (the two regression tests plus every
  pre-existing test in the file);
- run **hidden cases** that drive the same code path from inputs the upstream
  tests do not use: other non-ASCII characters and multi-diacritic names,
  wildcard patterns whose literal part is non-ASCII, the reverse direction
  (a decomposed rule against composed names), `prune`/`recursive-exclude` on
  non-ASCII directories, and an end-to-end `sdist` build whose archive must
  not contain the excluded file.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.