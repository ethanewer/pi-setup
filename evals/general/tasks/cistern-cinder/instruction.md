# Memory statistics must survive a /proc/meminfo field with no space after its colon

## Situation

`/app/src` is a shallow, pinned clone of `psutil` (the cross-platform Python
process and system-monitoring library, `https://github.com/giampaolo/psutil`)
checked out at upstream commit `afaaf9f340ff6561541f9f4781c58268b59abdac`.
The package is installed as an editable install (`pip install -e`), its C
extension is already compiled for this checkout, and pytest 9.1.1 (with the
project's own test-runner plugins) is installed. There is **no network** at
trial time: `git fetch`, `pip install` of new packages and any other network
use will fail.

The project's Linux test-suite is run from the checkout with the project's own
test runner:

```
cd /app/src && python3 -m pytest tests/test_linux.py -q
```

## The bug

On some Linux builds (arm64 kernels with shadow call stacks enabled), the
kernel's `/proc/meminfo` printer emits one field -- `ShadowCallStack` -- with a
fixed-width 8-digit payload. The moment that field's value reaches eight
digits, the width is exhausted: the kernel prints the name and the number with
**no space in between**, e.g.

```
ShadowCallStack:10373888 kB
```

Every other line in `/proc/meminfo` is `Name` + spaces + `value kB`. psutil's
function that reports overall system memory usage (`psutil.virtual_memory()`)
parses each meminfo line by splitting on whitespace, which silently collapses
`ShadowCallStack:10373888 kB` into `['ShadowCallStack:10373888', 'kB']` and then
tries to convert the `kB` token to an integer. On such systems the call aborts
with

```
ValueError: invalid literal for int() with base 10: b'kB'
```

before returning any statistics, so nothing can read total/free/available
memory (or compute percentages from them) at all.

## Reproducing the failure

Two ways, both ready in the image.

1. The probe script drives the public API directly against a crafted
   `/proc/meminfo`:

```
python3 /app/probe_meminfo.py
```

   It creates a scratch meminfo (with the no-space `ShadowCallStack` line),
   points `psutil.PROCFS_PATH` at it, and calls `psutil.virtual_memory()`.
   On this checkout it crashes with the `ValueError` above and exits nonzero.

2. The checkout already carries the project's regression test for this bug
   (it lives in `tests/test_linux.py`). Run just that test:

```
cd /app/src && python3 -m pytest tests/test_linux.py::TestVirtualMemoryMocks::test_virtual_memory_no_space_after_colon -q
```

   It fails on this checkout. Take its expectation
   (`mem.total == 100 * 1024` for a `MemTotal: 100 kB` layout) as part of the
   specification of correct behaviour.

When `psutil.virtual_memory()` is fixed, both of the above must succeed, and
the probe must report `total=102400` for the 100 kB layout.

## The task

Make `psutil.virtual_memory()` return the memory statistics instead of
crashing, for `/proc/meminfo` layouts that contain fields with no space after
the colon. Requirements:

- The regression test in `tests/test_linux.py` must pass.
- The rest of the project's Linux suite must stay green: everything in
  `tests/test_linux.py` passes at this commit except one class
  (`TestRootFsDeviceFinder`), whose tests compare psutil's partition
  resolution against the container's `findmnt` output and fail here purely
  for environment reasons, unrelated to this bug. Everything else --
  including the memory, cpu, load-average, disk and process tests -- must
  keep passing once you are done.
- Remember how psutil reads this file: the parsing is `line.split()` based and
  the value token is multiplied by 1024. Think about what "the value part of
  the line" means for lines whose name:value boundary is irregular. You may
  add your own scratch tests under `/app` or in `/tmp` to verify edge cases
  (fields with tabs, no trailing newline, 9- or 11-digit values, fields that
  appear nowhere else in the file); the verifier runs its own cases as well.

Change only what the fix requires, in place. The C extension does not need to
be rebuilt for a pure-Python fix (the editable install re-imports the changed
`.py`). If you re-run `pip install -e .` yourself, rebuild fully with
`pip install -e . --force-reinstall --no-deps` so the extension matches the
tree.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Do not rewrite history, add remotes, `fetch`,
  or change build files. Files under `/opt/golden`, `/tests` and `/solution`
  are harness-owned; do not touch them.
- The verifier also asserts that the working tree remains at the pinned
  commit, that the only tracked files modified are `tests/test_linux.py`
  (which carries the regression test and must stay exactly as it is) and the
  single source module your fix changes, and that no new files appeared
  inside the `psutil/` or `tests/` directories (you may create scratch files
  elsewhere, e.g. under `/app`).

## What the verifier checks

1. The tree is still at commit `afaaf9f340ff6561541f9f4781c58268b59abdac`,
   the working clone cannot reach any other upstream fix, the only tracked
   modifications are the overlaid regression test file and your source fix,
   `tests/test_linux.py` still matches its build-time copy byte-for-byte, and
   no new files appeared inside `psutil/` or `tests/`.
2. The project's upstream regression test
   (`test_virtual_memory_no_space_after_colon`) passes with the project's own
   test runner.
3. The project's own existing Linux tests (everything in `tests/test_linux.py`
   except the `findmnt`-comparison class) still pass.
4. Hidden cases pass: `/proc/meminfo` layouts with several no-space standard
   fields and 8/9/11-digit values, and the fallback code paths (no
   `MemAvailable` line; `MemAvailable` larger than total) reached with a
   no-space field present.

Deliverable: the repaired `/app/src` tree.