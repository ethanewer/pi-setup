# gale-ledge: drive the gale toolbox to green and ship a reproducible driver

You are given the `gale` computing library checked out at `/app/proj`. It has
grown a small test suite and some odd build/config constraints. Several source
modules are buggy or incomplete. Your job is to fix the bugs, install the
package editable, drive every test suite to green, record a confirmed passing
count, and ship a reproducible driver `/app/solve.py` plus a report
`/app/answer.json`.

Work **inside `/app/proj`**. The `tests/` tree and the manifest at the top of
the project describe ground truth — do not edit any test file, do not delete
tests, and do not alter the behaviour of the stable `col` engine. Write your
driver to `/app/solve.py` (make it executable) and make `python3 /app/solve.py`
regenerate all deliverables from scratch.

---

## The repository

```
/app/proj/
  pyproject.toml            setuptools project, package source under ./src
  manifest.json             release manifest: dependency matrix + source cap
  scripts/emit_manifest.py  compliance gate script
  tests/
    col/                    targeted suite (stable; must fully pass)
      conftest.py
      test_stack.py        3 tests
      test_compile.py      2 tests
    test_heap.py            GC-sweeper tests (currently failing)
    test_kinetic.py         model-composition tests (currently failing)
    fsx/test_async.py       async filesystem tests (import the installed pkg)
```

Package source (edit these):

* `src/gale/heap.py` — **GC-sweeper bug**. The arena keeps a run-length
  compressed list of free runs, each `[begin, length)`, that is maximally
  compressed (adjacent free cells are one run). `Arena.sweep()` must rebuild
  the free list from the live-cell bitmap. It currently **truncates the final
  cell of any free run that reaches the end of the arena**, so the arena under-
  reports free space and a full-arena live sweep can never hand back a complete
  block. This is why the healing/bootstrap block in `tests/test_heap.py` fails.
  Fix the sweep so a run that touches the arena end is counted in full, then
  `reclaimed_cells` equals the true free count and `contiguous(n)` returns a
  run of the requested size.

* `src/gale/kinetic.py` — **model-composition bug**. `compose(defs)` must fold a
  sequence of named 2x2 models **left-to-right**:
  `compose([(n1,M1),(n2,M2),(n3,M3)]) == (M1 @ M2 @ M3)` and the second return
  value is `"n1|n2|n3"`. `matmul(a,b)` computes the row-major 2x2 product
  `a @ b`. The composition currently folds the matrices in the wrong order, so
  the multi-matrix assertions in `tests/test_kinetic.py` fail. Fix the fold
  order without changing `matmul`.

* `src/gale/io.py` — **missing async filesystem method**. `slurp_tree(root)`
  must be an async function returning a dict `{relative_path: text}` for every
  regular file under `root` (recursively), using `/` separators, with the file
  text preserved verbatim. It is currently a stub that raises
  `NotImplementedError`. Implement it, then reinstall the package editable
  (`python -m pip install --no-build-isolation -e /app/proj`) so the new
  method is visible to the **installed** `gale` package. Run
  `tests/fsx/test_async.py`, which imports the installed package and requires
  `gale` to be present in the distribution metadata.

## The targeted suite and its confirmed count

`tests/col/` is the target suite: it must run to a **full successful pass** and
you must record that pass count. Run:

```
cd /app/proj
python -m pytest -q tests/col
```

and capture the output into `/app/colib.log` so it contains the pytest summary
line such as `===== 5 passed in 0.02s =====` (the number is the confirmed pass
count of this suite). The suite has **5** passing tests; if your `col` engine
or test edits shift it, the verifier's independent count decides.

## Dependency-matrix and source-size compliance

The release manifest `/app/proj/manifest.json` declares a dependency matrix
(`dependencies`) with minimum versions and a hard source-size cap
(`source_cap_bytes`). `scripts/emit_manifest.py` is the compliance gate: it
checks that every declared dependency is installed at a version >= its minimum
and that no regular file under `src/` exceeds the cap. Run it with:

```
python /app/proj/scripts/emit_manifest.py
```

It must print exactly `MANIFEST COMPLETE` and exit 0. Make the environment and
the source satisfy the manifest (the standard tooling is already installed;
you may adjust the manifest if its declared cap no longer matches a justified
fixed module, but keep the declared runtime dependencies realistic).

Hard constraint (enforced independently by the verifier, not stored in the
manifest): **no regular file under `src/` may exceed 3000 bytes**. Keep your
fixes tight.

## Deliverables

1. `/app/solve.py` — a reproducible driver (executable) with two modes:

   * **Default** (`python3 /app/solve.py`): perform the whole pipeline and
     write `/app/colib.log` (the col-suite summary with the confirmed pass
     count) and `/app/answer.json`:
     ```json
     {
       "project": "gale-ledge",
       "install_ok": true,
       "colib_passed": 5,
       "col_suite_ok": true,
       "suites_ok": true,
       "asyncfs_ok": true,
       "manifest_ok": true,
       "size_cap_ok": true,
       "emit_print": true
     }
     ```
     `install_ok` is whether the editable install succeeded; `colib_passed` is
     the parsed col pass count; `suites_ok` is whether the heap + kinetic +
     fsx suites all pass; `manifest_ok` and `size_cap_ok` reflect the
     dependency-matrix and source-size gates; `emit_print` is whether the
     gate printed `MANIFEST COMPLETE`. Re-running `python3 /app/solve.py` must
     reproduce the same state from a clean in-container working copy.

   * **Status** (`python3 /app/solve.py status --manifest M [--src S]`): used
     by the verifier on **fresh and malformed** fixtures mounted read-only. It
     must print a JSON object `{"manifest_ok": bool, "size_cap_ok": bool,
     "violations": [...]}` and **never crash** — a malformed (non-JSON) or
     missing manifest, or an oversized `src` file, must be reported in
     `violations` / the boolean flags rather than raise an exception. The
     compliance and size checks here must be data-driven (they run against
     paths that are not `/app/proj`).

2. `/app/answer.json` — the report written by the default run.

## How you will be graded (read-only, once you finish)

The verifier re-invokes `/app/solve.py`, then independently re-checks: the col
suite passes fully and `/app/colib.log` confirms the matched pass count; the
package editable-installs and the async filesystem tests pass from the
installed `gale`; the focused `test_heap.py` + `test_kinetic.py` subset passes
without regressing the rest of the suite; `emit_manifest.py` prints
`MANIFEST COMPLETE`; no `src` file exceeds 3000 bytes; `answer.json` reports
all gates true; and the `status` subcommand handles fresh/malformed hidden
fixtures correctly. Nothing else is checked.
