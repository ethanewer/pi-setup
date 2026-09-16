# chainplate-bollard

You are working inside a real open-source codebase: **NetworkX**
(`networkx/networkx`), the Python graph-analysis library, checked out at a
pinned commit in `/app/src` (working tree clean, detached HEAD). There is a
bug in this tree's spanning-tree iterator. Your job is to find it, fix it in
the working tree, and prove the fix with the project's own test tooling.
You are deliberately **not** told which file or line to change: localising
the bug is part of the task.

## Environment

- Python 3.12 with `pytest 9.1.1` installed. The repository is installed
  editable (`pip install -e /app/src`), so `import networkx` resolves to the
  tree at `/app/src`. Do not reinstall or uninstall anything. `numpy` and
  `scipy` are **not** installed; the parts of the project's test suite that
  need them skip themselves.
- **There is no network** in this container. Everything you need is already
  on disk; `pip install` and `git fetch` will not work.
- `cpus = 1`: one vCPU.
- `/app/src` is a shallow clone (one commit, detached HEAD). Do not commit,
  fetch, add remotes, or otherwise modify `.git`.

## The bug (user-visible symptom)

`nx.SpanningTreeIterator(G)` is a public iterator that yields, one by one,
every spanning tree of a graph `G`, in increasing order of total weight.
Python's iterator protocol allows *either* of these spellings, and they are
supposed to be equivalent:

```python
for tree in nx.SpanningTreeIterator(G):   # iter() is implicit
    ...
```

```python
it = nx.SpanningTreeIterator(G)
first = next(it)                          # no iter() call, still valid
```

In this checkout the second spelling is broken. Calling `next()` directly on
a freshly constructed iterator object — exactly as the protocol permits,
without first invoking `iter()` — raises an `AttributeError` about a missing
internal attribute instead of returning the next spanning tree. The first
element of the sequence is impossible to obtain this way, even though the
object advertises itself as an iterator (`__iter__` and `__next__` are both
defined). Every user of the iterator that goes through a `for` loop or
`list(...)` appears to work, because those paths call `iter()` implicitly and
hide the defect.

Reproduce it:

```bash
cd /app/src
python -c "import networkx as nx; print(next(nx.SpanningTreeIterator(nx.cycle_graph(3))))"
```

On the buggy tree this raises

```
AttributeError: 'SpanningTreeIterator' object has no attribute 'partition_queue'
```

After a correct fix it must print a `Graph` that is a spanning tree of the
3-cycle (i.e. a 2-edge tree on nodes `{0, 1, 2}`).

## Requirements

1. Fix the tree so that direct `next()` calls on a `SpanningTreeIterator`
   work and return the spanning trees exactly as the `for`-loop spelling
   does — including the first one, and including after `next()` has been
   called repeatedly until the sequence is exhausted (then it must raise
   `StopIteration` as before). This is a general protocol-contract fix, not
   a special case for 3-cycles: it must work for weighted and unweighted
   graphs, for both `minimum=True` (default) and `minimum=False`, and for
   `nx.MultiGraph` inputs.
2. Keep everything else working. The project's own test file
   `networkx/algorithms/tree/tests/test_mst.py` is green on the pristine
   tree (its existing spanning-tree tests all go through `for` loops) and
   must stay green after your fix.
3. The graded tree must be byte-identical to the pinned commit except for
   the **single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify the tests,
   `pyproject.toml`, `requirements/` or any metadata file.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the snippet above. Read the traceback: it names the
   attribute that does not exist. Note that the `for`-loop spelling works —
   that difference is the whole puzzle.
2. **Localise**: find where the missing attribute is supposed to be created.
   It is initialised in exactly one place, and that place is only ever
   reached through `iter()`. Understand *why* the protocol still allows
   `next()` to be called first, and why that bypasses the initialisation,
   before you patch. The class also has to keep behaving the same way when
   iteration is exhausted (`StopIteration` is raised, and the internal state
   is cleaned up).
3. **Fix** with the smallest possible change, re-run the reproduction, then
   run the project's own tests for the module:
   `python -m pytest networkx/algorithms/tree/tests/test_mst.py -q -p no:cacheprovider`
   — they pass on the pristine tree and must keep passing after your fix
   (the grader additionally plants an upstream regression test that this
   tree does not contain yet).
4. Sanity-check the contract on inputs the reproduction does not use: a
   `MultiGraph`, `minimum=False`, a weighted graph, and exhausting the whole
   sequence with direct `next()` calls.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream fix
  commit is not reachable from the working clone, and that every tracked file
  except the single source file the bug lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`; upstream added it with the fix, so it does not
  exist in this tree) into the tree's `test_mst.py` and run that whole file —
  the regression test must pass **and** the project's pre-existing mst tests
  must stay green;
- run **hidden cases**: direct-`next()` drives of the same iterator that the
  upstream regression test does not use — an unweighted 4-cycle driven to
  exhaustion (count of trees checked against Kirchhoff's theorem), a weighted
  wheel graph in both the minimum and maximum directions, and a `MultiGraph`
  input.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.