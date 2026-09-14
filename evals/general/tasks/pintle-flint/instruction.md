# Region property measurement keeps computed data behind long after use even when caching is disabled

## Situation

`/app/src` is a shallow, pinned clone of the scikit-image library
(`https://github.com/scikit-image/scikit-image`, scientific image processing in
Python), checked out at upstream commit `9107d523a899b8d3767630941ac28f438bf875d2`,
and installed from that tree in editable (development) mode, so `import skimage`
resolves to the checked-out Python source and edits you make are picked up
immediately. Python 3.12, NumPy 2.1.3, SciPy 1.14.1, matplotlib, and pytest are
installed. There is **no network** at trial time: everything you need is already
in the image; `pip` and `git fetch` will not work.

## The bug

`skimage.measure.regionprops` measures labelled objects (blobs) in an image:
for each region it can report properties such as area, bounding box, centroid,
axis lengths, intensity statistics, moments, and so on. Computing these is
expensive, so the library memoizes each measurement inside the region object:
the first read of a property computes and stores it, later reads return the
stored value. That memoisation can be switched off for memory-constrained
pipelines by calling `regionprops(..., cache=False)`.

`cache=False` is documented to mean **"do not retain computed properties"**:
each property should be computed on demand and discarded, so a region object
does not keep its computed measurements around. In this checkout that contract
is broken. A region object created with `cache=False` still accumulates every
property that is read into a private stash inside the object, and it keeps the
stash for its whole lifetime. A pipeline that processes many images or many
regions with caching disabled therefore holds on to every computed array —
including large measurement images such as per-region binary masks or the
original regions' intensity crops — until the region objects are themselves
discarded, which defeats the entire purpose of disabling the cache.

The intended contract, which the fix must restore:

| configuration | contract |
| --- | --- |
| `cache=False` | reads are computed fresh every time; **nothing** read may remain stored inside the region object afterwards (its internal stash must be empty); returned values are exact |
| `cache=True` (default) | unchanged behaviour: each measurement is computed once and reused on later reads; returned values are identical to today's |

Note that the bug is invisible through the returned values alone — property
values are the same whether or not the stash fills up. Observing it requires
looking at the region object's internal state (or at memory growth).

## What you need to do

1. **Write your own failing reproduction first**, as a deliverable at
   `/app/repro.py`, before changing any source. Requirements:

   - a self-contained Python 3 script using only the installed packages
     (`skimage`, `numpy` — nothing else);
   - it constructs regions with `cache=False`, reads several distinct
     properties (at least three different ones, including at least one
     intensity property and one array-valued property), and then inspects
     the actual internal state of the region object to count how many
     computed properties it is still holding;
   - it prints exactly one line `retained=<n>` with that count;
   - it exits with status `0` exactly when `n == 0`, and with any non-zero
     status when `n > 0`;
   - it must derive its verdict from the real library behaviour it observes
     (a hardcoded `0` or unconditional success is a non-solution: the
     verifier will run it against this buggy checkout too and require a
     non-zero exit there).

   Run it now, before touching the source: it must currently exit non-zero
   (the bug is present). Leave the script at `/app/repro.py`.

2. **Repair the checked-out tree at `/app/src`** so that the contract table
   above holds: with `cache=False` nothing read is retained, while
   `cache=True` keeps its exact current caching semantics and every returned
   value is unchanged. Change only the minimal source needed for the fix, in
   place.

3. Drive the work with the project's own test runner, from `/app/src`:

   ```
   cd /app/src && python3 -m pytest skimage/measure/tests/test_regionprops.py -q -p no:cacheprovider
   ```

   That whole module is green at the pinned commit; keep it green. Your
   `/app/repro.py` must additionally exit `0` once your fix is in (run it with
   `cd /app/src && python3 /app/repro.py`).

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone at `/app/src` is part of the deliverable. Do not rewrite history,
  do not add remotes, do not fetch, do not change build or packaging files,
  and do not add or commit any file inside the clone: the verifier requires
  the working tree to contain **exactly one** modified tracked file (your
  fix), with `HEAD` still at the pinned commit.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them. `/opt/golden` holds the upstream regression test for this
  bug, extracted at image build time; the verifier runs it against your tree
  and its hash is pinned.

## What the verifier checks

1. **Provenance**: `HEAD` is still the pinned commit, the upstream fix commit
   was never pulled into the clone, the working tree contains exactly one
   modified tracked file, and `/app/repro.py` exists.
2. **Interpreter hygiene**: no import-time hooks or shadow copies of `skimage`
   anywhere on the interpreter path (the fix must live in the tracked source,
   and the verifier confirms the module it runs actually resolves to
   `/app/src`).
3. **Upstream regression test**: the fix-commit regression test extracted to
   `/opt/golden` passes against your tree.
4. **Your reproduction, both directions**: `/app/repro.py` exits `0` on your
   repaired tree; the verifier then momentarily reverts your fix (`git stash`)
   and requires `/app/repro.py` to exit non-zero there — so your reproduction
   must genuinely distinguish the buggy tree from the fixed one — and requires
   the golden test to fail there too, then restores your fix.
5. **Hidden cases**: additional cases over inputs the upstream test does not
   use (a 3-D volume; a multi-region image with holes and float intensities)
   pass: with `cache=False` no region retains anything; with `cache=True`
   caching still happens; all values agree between the two modes.
6. **No regressions**: the project's own `test_regionprops.py` module stays
   fully green.

Deliverables: `/app/repro.py` and the repaired `/app/src` tree.