# Swap memory reporting crashes with ValueError on certain Linux kernels

## Situation

`/app/src` is a shallow, pinned clone of the psutil repository
(`https://github.com/giampaolo/psutil`) at upstream commit
`5ec16ad4d887c069f6b758fd0659fb6bc9b47f7d`, checked out in detached HEAD.
The package is already installed in **editable mode**: `import psutil`
imports the code under `/app/src`, and any change you make to the Python
sources under `/app/src/psutil/` takes effect on the next interpreter run —
no reinstall and no compilation are needed for Python-only changes (the C
extension is already built). `pytest` (plus the project's required pytest
plugins) is installed, and the project's own test suite lives under
`/app/src/tests`.

There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail. Everything you need is on disk.

## The bug

On some Linux systems—most commonly arm64—the kernel prints one field of
`/proc/meminfo` with **no space after its colon**, e.g.:

```
ShadowCallStack:10373888 kB
```

(the kernel formats that particular counter with a fixed-width `%8lu`
format, which omits the space once the value reaches 8 digits / ~10 GB).

On any such system, **reading the swap memory usage crashes outright**
instead of returning the total/free/used/percent figures. The failure is a
`ValueError`:

```
ValueError: invalid literal for int() with base 10: b'kB'
```

Impact: any program that queries swap usage—total, used, free, percent,
swap-in/swap-out rates, i.e. `psutil.swap_memory()`—fails entirely on
affected machines. Swap monitoring breaks, while ordinary physical-memory
reporting keeps working.

## What you must deliver

Two deliverables, both under `/app`:

### 1. `/app/reproduce.py` — your own reproduction script

A self-contained Python file, written by you for this task, that
demonstrates this crash **without needing an affected machine**. The
intended mechanism is a synthetic `/proc` substitute: psutil exposes a
documented, public, writeable module-level constant that redirects its
procfs reads to a directory of your making (find it in the project's docs
under `/app/src/docs/` and among the public exports of
`/app/src/psutil/__init__.py`). Your script must create such a substitute,
populate its `meminfo` with content that includes a no-space-after-colon
field, and call the affected functionality.

The script's behaviour contract (the verifier will rely on exactly this):

- when the bug is present (untouched pre-fix code), it must terminate
  nonzero, having printed the genuine failure—the `ValueError` traceback,
  i.e. the text `ValueError: invalid literal for int() with base 10: b'kB'`;
- when the bug is fixed, it must exit 0 and print exactly one line of the
  form

  ```
  swap total=<total> free=<free> used=<used> percent=<percent>
  ```

  with byte counts as integers and percent as a float, e.g.
  `swap total=15360 free=14336 used=1024 percent=6.7` for a meminfo where
  SwapTotal is 15 kB and SwapFree 14 kB.

The verifier runs **this exact script twice**: once against a fresh,
untouched pre-fix copy of the code, and once against your repaired tree. It
must crash with the ValueError on the former and succeed with consistent
figures on the latter.

### 2. The fix, in the checked-out tree

Repair the swap memory reporting in `/app/src` so that:

- `/app/reproduce.py` succeeds as specified above;
- the project's own regression test for this behaviour
  (`tests/test_linux.py::TestSwapMemory::test_no_space_after_colon`) passes;
- swap reporting is correct on real machines too (total, free, used and
  percent values come out right regardless of which meminfo fields are
  space-separated and which are not, and regardless of line order).

The tests that ship in the tree are the spec: run them, read them, drive
your work with them. The regression test is already present in the tree at
`/app/src/tests/test_linux.py` and currently fails: that failing test is
the project's own (upstream) expression of exactly this bug.

## Constraints

- Change in place only what the fix requires. Do not rewrite history, add
  remotes, fetch, commit, or modify build files inside `/app/src`, and do
  not modify the tests under `/app/src/tests/` (the verifier checks them
  byte-for-byte against the upstream versions).
- `/opt/golden`, `/opt/pristine`, `/tests` and `/solution` are
  harness-owned; do not read or modify them.
- The working tree at `/app/src` and your `/app/reproduce.py` are the
  deliverables.

## What the verifier checks

1. Tree provenance: still at the pinned commit; the upstream fix commit is
   not reachable in the clone; the only tracked difference besides the
   overlaid regression test is the minimal source change; the overlaid test
   file is byte-identical to the upstream regression test.
2. `/app/reproduce.py` against a pristine **pre-fix** tree: must crash with
   the genuine `ValueError` (this proves your reproduction actually
   demonstrates the bug and is not a stubbed or vacuous script).
3. `/app/reproduce.py` against your repaired tree: must exit 0 and print
   consistent total/free/used/percent figures.
4. The project's own suite for the affected area: the full `TestSwapMemory`
   class (including the regression test you must make pass) plus
   `TestVirtualMemory::test_virtual_memory`, all green.
5. Additional hidden cases with meminfo contents the upstream test does not
   use: `psutil.swap_memory()` must return the exact expected
   total/free/used/percent values.

Run `python -m pytest tests/test_linux.py::TestSwapMemory::test_no_space_after_colon`
inside `/app/src` to see the failing regression test, and use
`/app/reproduce.py` as your own end-to-end check of both directions.