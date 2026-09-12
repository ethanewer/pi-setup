# A silent out-of-bounds bug in the libvips image library

This is a debugging task inside a real upstream codebase, in the SWE-bench
style: you are handed a genuine regression in a C library you did not write,
a failing behaviour, and a reproducer -- but not the file, the function, or
the line that is wrong. You must localise the defect in the real source
tree, repair it at its root, rebuild the library, and write a short
diagnosis.

## Environment

- `/app/src` is a working copy of the real **libvips** C image-processing
  library (`https://github.com/libvips/libvips`), checked out at a fixed
  upstream commit (shallow git repo, branch `baseline`). The tree is
  complete and editable and has working git metadata; you may commit if you
  like, but you do not have to.
- The tree has **already been built** with the project's own build system
  (meson + ninja) and **already installed** system-wide. The installed
  library is the build of this exact tree -- i.e. it contains the bug.
  `pyvips` (the Python binding) is installed and bound to that installed
  library, and `pytest` is available.
- There is **no network** in this container. You cannot fetch anything,
  re-clone, or `pip install` anything. Everything you need is in the image.
- Exactly **1 CPU** is available. The full build was done once at image
  creation; your rebuild only needs to recompile what you change.

## The failing behaviour

One of libvips' drawing operations pours a fill across the pixels connected
to a start point. When that start point lies **outside the image** -- past
the right or bottom edge -- the operation is **silently ignored**: the call
returns success, nothing is drawn, and the caller gets no signal at all that
its coordinates were invalid. A start point past the top or left edge
(negative coordinates) fails too, but with an **opaque property error** that
does not say the point is out of bounds -- so callers of the library cannot
reliably tell "invalid start point" from anything else. Real-world callers
compute fill coordinates without clamping and trust the library to tell
them when a fill cannot start.

Concretely, on the 100x100 image below the operation should refuse a start
at (200, 50) or (50, 200) with a clear error. Instead it "succeeds" and
draws nothing:

```python
im = pyvips.Image.black(100, 100)
im.draw_flood(100, 200, 50)   # silently accepted, no error, nothing drawn
```

Reproduce it with:

```bash
python3 /app/reproduce.py
```

While the bug is present it prints something like

```
BUG: draw_flood start x past the right edge (x=200, y=50): no error raised, coordinates silently accepted
BUG: draw_flood start y past the bottom edge (x=50, y=200): no error raised, coordinates silently accepted
ok: in-bounds flood from the centre fills the whole black 64x64 region
BUG REPRODUCED: 2 check(s) failed
```

and exits non-zero. After the library is fixed it prints

```
ok: draw_flood start x past the right edge (x=200, y=50) raised: draw_flood: start point out of image
ok: draw_flood start y past the bottom edge (x=50, y=200) raised: draw_flood: start point out of image
ok: in-bounds flood from the centre fills the whole black 64x64 region
OK: out-of-bounds starts are rejected with an error and valid floods still work.
```

and exits 0.

## What to do

1. Observe the failing behaviour with `/app/reproduce.py`.
2. Localise the defect in the real source tree under `/app/src`. The
   operation involved is the one behind pyvips' `draw_flood` (and its
   single-ink variant `draw_flood1`); search the C sources for that
   operation's implementation. Keep your search targeted -- running or even
   reading the whole tree is not needed. Note the two different failure
   styles in the description: one coordinate direction is silently ignored
   while the other trips an unrelated, confusing property check before the
   operation even starts. The silent case is the real gap.
3. Fix the cause in the C source. Do **not** modify any test files, do
   **not** add Python-side post-processing or a wrapper that papers over the
   wrong behaviour, and do **not** special-case particular input values. The
   root cause is one missing validation step; repair it at its source so
   every start point outside the image is rejected with a clear error while
   every valid start point keeps working.
4. Rebuild and reinstall the changed library (only what changed recompiles):

   ```bash
   cd /app/src && ninja -C build install
   ldconfig || true     # may be a no-op depending on the uid you run as
   ```

   (`ldconfig` merely refreshes the loader cache; the installed library is
   picked up either way.) Then re-run `/app/reproduce.py` -- it must exit 0.
   Sanity-check with a second shape, e.g. an image containing a hole or a
   shape, and confirm the fill still travels exactly across the connected
   region.
5. Make sure the project's own relevant test still passes. libvips' test
   suite lives under `/app/src/test/test-suite/` (run from that directory):

   ```bash
   cd /app/src/test/test-suite && python3 -m pytest test_draw.py -q
   ```

   This draw test file must stay green after your change. (Note: the suite
   as it exists in this tree does **not** cover the out-of-bounds case that
   `/app/reproduce.py` exercises -- that is exactly why the bug slipped
   through upstream -- so a green suite is necessary but not sufficient;
   `/app/reproduce.py` is your real regression check.)

## Deliverables

Both are checked.

1. **The repaired source tree in `/app/src`** -- your fix as ordinary edits
   in the C source, and the rebuilt, reinstalled library derived from it.
   The tree must otherwise remain exactly as checked out: do not change
   tests, documentation, build config, or other modules.
2. **`/app/diagnosis.md`** -- a short root-cause note (a few sentences, in
   your own words) stating:
   - **where** the defect lives (the module/directory in the C sources),
   - **the root cause**: what the code did wrong, why an out-of-range start
     on one side was silently ignored while the other side tripped an
     unrelated property error instead of a bounds check,
   - **the fix**: the minimal change you applied.

## Constraints

- Do not modify `/app/reproduce.py` or anything under `/tests` (you cannot
  see the verifier anyway).
- Do not remove, rename or replace the clone at `/app/src`; repair it in
  place.
- No network, 1 CPU: the rebuild must be incremental or it will not finish.