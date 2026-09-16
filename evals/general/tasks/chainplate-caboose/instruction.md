# Backslash member names escape archive extraction

## Situation

`/app/src` is a shallow, pinned clone of the setuptools repository
(`https://github.com/pypa/setuptools`) at commit
`bb1b38189eed960bdb4f4789926472d05e43d335`, checked out in detached HEAD.
The project is installed from this tree in editable mode, so
`pip install -e '.[test]'` already ran at image build time and `import
setuptools` resolves to `/app/src/setuptools`. Python 3.12.13, `pytest`
8.4.2 and the project's test dependencies are installed.

There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail. Everything you need is on disk.

The file `setuptools/tests/test_archive_util.py` in this tree is the
project's own regression test module for the behaviour you will fix. It has
been updated to the upstream revision that exercises this bug, so you can
watch the bug through the project's own test runner:

```
cd /app/src && python3 -m pytest -q setuptools/tests/test_archive_util.py
```

Right now that run ends with `7 failed, 7 passed, 1 xpassed`: the failing
tests are exactly this bug, and the same module describes the behaviour your
fix must restore. You may run the project's tests as often as you like, but
you must not modify that test file (or any test) — the verifier checks it is
untouched. Do not modify the `.git` directory or rewrite history in any way.

## The bug

setuptools can unpack zip and tar archives to a directory through
`setuptools.archive_util.unpack_archive()`. An archive is just a byte soup
from an untrusted source, and its member names are attacker-controlled.

Both archive formats specify `/` as their only path separator. The
extraction code's path-traversal guard, however, only looks for `..`
components after splitting member names on `/`. A member name that uses a
backslash instead of a slash — or that carries a drive letter or a UNC
prefix — therefore slips straight past the guard:

- `..\escaped.txt` is one `..`-free component to the guard, but on Windows
  the backslash makes the filesystem resolve it as `..`/`escaped.txt`
  **outside** the destination directory, so a crafted archive can plant
  files anywhere on the machine;
- `C:evil.txt` and `\server\share\evil.txt` are likewise `..`-free to the
  guard, but on Windows the drive letter / UNC prefix throws away the
  destination directory entirely;
- on non-Windows platforms the same members are not a traversal, but they
  still extract as surprising literal file names full of backslashes, and
  the code below is supposed to reject them uniformly on every platform.

Reproduce it (works offline, needs nothing but the installed package):

```python
python3 - <<'PY'
import io, tarfile, tempfile, os
from setuptools import archive_util

tmp = tempfile.mkdtemp()
tgz = os.path.join(tmp, 'malicious.tar.gz')
with tarfile.open(tgz, mode='w:gz') as t:
    for name in ['..\\escaped.txt', 'inside.txt']:
        info = tarfile.TarInfo(name)
        data = name.encode(); info.size = len(data)
        t.addfile(info, io.BytesIO(data))
dest = os.path.join(tmp, 'dest')
archive_util.unpack_archive(tgz, dest)
names = sorted(os.path.relpath(os.path.join(r, f), dest) for r, d, fs in os.walk(dest) for f in fs)
print('EXTRACTED:', names)
assert names == ['inside.txt'], names
PY
```

It prints `EXTRACTED: ['..\\escaped.txt', 'inside.txt']` and the assertion
fails — the escaped member was extracted even though it must not be.

## Deliverable

The deliverable is the repository at `/app/src`, fixed in place. You are
expected to change exactly one existing source module of the project — the
module in `/app/src/setuptools/` that performs the extraction and contains
the flawed guard — and nothing else. The verifier will fail your work if it
sees changes to any other file, so do not touch the tests, the build
configuration, or unrelated code.

The fix must make all of the following hold inside the repaired tree:

1. Unpacking an archive never creates anything outside the extraction
   directory, on any platform. Member names that would escape — including
   `..` components in `/`-separated form, backslash-separated components,
   drive-qualified names and UNC-prefixed names — are skipped, and a member
   that would silently land outside is not extracted.

2. Safe members of the same archive are still extracted exactly as before
   (this is the harder half: rejecting everything would satisfy the first
   clause but break the project's own tests).

3. The project's own test module passes completely:

```
cd /app/src && python3 -m pytest -q setuptools/tests/test_archive_util.py
# -> 14 passed, 1 xpassed   (the xfail is a pre-existing unrelated case)
```

4. The reproduction above prints `EXTRACTED: ['inside.txt']` and its
   assertion passes; the zip and tar drivers behave the same way.

The verifier re-runs the project's tests and additional hidden cases itself
after you are done, so make sure the fixed tree is the state you leave it
in. A correct fix is a few dozen lines in one file; you will know you are
done when the pytest run above is green.