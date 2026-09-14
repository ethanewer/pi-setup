# Fix the all-black output of ICC profile imports on float images

## Situation

`/app/src` is a shallow, pinned clone of the libvips project
(`https://github.com/libvips/libvips`) at upstream commit
`f0c38f9a7d4bea39e1e1718db2b441c91880a871`, checked out in detached HEAD.
The tree has already been configured and compiled: a meson build directory
exists at `/app/src/build` (prefix `/usr`), a full `ninja` build succeeded,
and the built libraries were installed system-wide. Everything runs offline.

What is installed:

- `python3` with `pyvips` 3.2.0 and `pytest` 8.3.5 (installed via pip with
  `--break-system-packages`).
- libvips itself is installed system-wide at `/usr/lib/x86_64-linux-gnu/`
  (libvips.so.42). That system copy is the **buggy** parent build and is owned
  by root: you cannot and must not reinstall over it (`ninja install` writes
  into root-owned `/usr` and will fail for you).
- The project's image fixtures live in `/app/src/test/test-suite/images/`
  (`sample.jpg`, `sample.png`, `sRGB.icm`, and more).
- The project's own colour and conversion test modules pass on this tree:

```
cd /app/src/test/test-suite
python3 -m pytest test_colour.py test_conversion.py -q     # 50 passed
```

## The bug

A user reports:

> "When I convert a colour photo to a float image — each band holding the
> usual 0..1 range of values — and then apply an ICC colour profile with
> `icc_import()`, the result is completely black. The identical photo in
> ordinary 8-bit form converts correctly and shows the expected colour
> shift. Nothing errors; the operation silently returns a plain black image
> (average pixel value 0)."

That report is reproducible on this tree. A float image with RGB values in
the usual 0..1 range, passed through `icc_import(input_profile=...)` with an
in-repo profile, comes back all black; the same image as 8-bit bytes
transforms correctly (its average lands around 19 on the sample photo). Watch
out: the operation raises no error at all, so the only signal is the pixel
data itself.

## What you need to do

Deliverable 1 — `/app/reproduce.py`, your failing reproduction, written
**first**, before you change anything:

- A small, self-contained `python3` script (no pytest) that uses **pyvips**
  to demonstrate this bug on this tree: load a fixture image from
  `/app/src/test/test-suite/images/`, convert it to float holding 0..1
  values, apply `icc_import` with an in-repo profile, and fail (exit
  non-zero, printing the observed value) when the import came out black.
  Use absolute paths only, so it works from any working directory.
- Contract: run as `/app/reproduce.py` (make it executable). Against the
  current tree it must exit non-zero — that is the reproduction failing. After
  the bug is repaired it must exit 0.
- Write this before touching the source, and leave it in place: the verifier
  runs it against the pristine pre-repair build (it must still detect the
  bug) and again against your repaired build (it must pass).

Deliverable 2 — `/app/src`, the repaired checkout. Fix the bug in the
checked-out sources so the reported symptom disappears:

- A float image in the 0..1 range must transform the same way the
  equivalent 8-bit image does: the float import must be non-black (average
  well above 1 on the sample photo) and must be within tolerance of the
  8-bit import of the same image (per-pixel absolute difference below 3).
- 8-bit and 16-bit imports must keep working exactly as before, and the
  project's colour and conversion tests must stay green.

## How to test your work

Rebuilding after an edit is incremental; the meson build directory is already
configured:

```
cd /app/src
ninja -C build -j1                # recompiles and relinks just what changed
```

A rebuilt library takes effect through the in-tree build directory. Do not
touch `/usr`:

```
export LD_LIBRARY_PATH=/app/src/build/libvips
python3 /app/reproduce.py         # your reproduction, now expected to pass
```

The system-wide copy stays the pristine parent build and is what the
verifier uses to confirm that your reproduction genuinely detects the bug.

## Constraints

- No network is available at trial time; do not attempt to download
  anything, do not add git remotes, do not fetch.
- Work inside `/app/src` only in the way the fix requires: keep the checkout
  at its pinned commit, do not rewrite history or commit, and leave no new
  or untracked files inside the repository (put scratch work in /tmp or
  /app). Any change to tracked files must be under the `libvips/` tree.
- Do not modify or delete anything under `/opt/golden`, `/tests` or
  `/solution` — those are harness-owned.
- `/app/reproduce.py` must use the project's real machinery (`pyvips` +
  `icc_import`), not a stub.

## What the verifier checks

1. `/app/reproduce.py` exists, is executable, and is a genuine pyvips
   reproduction; run against the pristine parent build it must exit
   non-zero, and against the rebuilt repaired tree it must exit 0.
2. The tree is still at the pinned commit, the working-tree diff contains
   exactly your source repair (tracked modifications only, all under
   `libvips/`, no untracked files), and the pristine system build is
   byte-identical to the parent build.
3. A full clean rebuild of the project from your tree (`ninja clean` +
   `ninja -C build -j1`), then:
   - the project's own regression test for this behaviour (the float-input
     ICC test from upstream, run via pytest) passes;
   - the project's own `test_colour.py` and `test_conversion.py` suites pass
     in full;
   - hidden cases exercising the same code path on inputs the upstream
     regression test does not use pass: float imports of a different fixture
     image (PNG) and of `double`-bandformat constant colours, each checked
     to be non-black and within tolerance of the corresponding 8-bit import.

Treat the project's own behaviour as the spec: the float path must behave
like the 8-bit path.