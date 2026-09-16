# ballast-overtake

You are working inside a real open-source codebase: **NetworkX**
(`networkx/networkx`), the Python graph-analysis library, checked out at a
pinned commit in `/app/src` (working tree clean). There is a bug in this
tree's HITS hub/authority implementation. Your job is to find it, fix it in
the working tree, and prove the fix with the project's own test tooling.
You are deliberately **not** told which file or line to change: localising
the bug is part of the task.

## Environment

- Python 3.12.13 with `numpy 2.5.3`, `scipy 1.18.1` and `pytest 9.1.1`
  installed. The repository is installed editable
  (`pip install -e /app/src`), so `import networkx` resolves to the tree at
  `/app/src`. Do not reinstall or uninstall anything.
- **There is no network** in this container. Everything you need is already
  on disk.
- `cpus = 1`: one vCPU, and BLAS/LAPACK kernels are pinned to one thread.
- `/app/src` is a shallow clone (one commit, detached HEAD). Do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

HITS assigns every node of a graph two non-negative scores: a *hub* score
and an *authority* score. NetworkX implements HITS in several ways; one
internal implementation computes the scores from dominant eigenvectors of
the hub/authority matrices using `numpy.linalg.eigh` and, when asked not to
normalize, scales each score vector by its largest component.

For certain perfectly ordinary small undirected graphs this implementation
returns scores that are **not finite numbers** (`inf`/`nan`) or that are
**negative**, where finite non-negative scores are expected. The failure is
deterministic for the graphs that trigger it, and a
`RuntimeWarning: divide by zero encountered in divide` is printed on stderr.

The affected routine is `_hits_numpy(G, normalized=False)` (the internal
numpy/eigenvector HITS backend; the default `nx.hits` power-iteration
method and `nx.hits(..., method="svd")` are not affected). Reproduce it:

```bash
cd /app/src
python - <<'PY'
import numpy as np
import networkx as nx
from networkx.algorithms.link_analysis.hits_alg import _hits_numpy

G = nx.path_graph(3)  # a 3-node path
hubs, authorities = _hits_numpy(G, normalized=False)
print("hubs:", hubs)
print("authorities:", authorities)
print("hubs finite:", all(np.isfinite(v) for v in hubs.values()))
print("authorities finite:", all(np.isfinite(v) for v in authorities.values()))
print("hubs non-negative:", all(v >= 0 for v in hubs.values()))
print("authorities non-negative:", all(v >= 0 for v in authorities.values()))
PY
```

On the buggy tree this prints a `RuntimeWarning: divide by zero` and some
`inf`/`nan` or negative values. After a correct fix it must print all-finite
and all-non-negative values with **no** warning.

## Requirements

1. Fix the tree so that `_hits_numpy(G, normalized=False)` returns finite,
   non-negative scores for **every** undirected graph, with no division
   warnings. The same defect is reachable from other small graphs (longer
   paths, disconnected unions of paths — see Grading), so do not special-case
   the input above; fix the scaling itself.
2. Keep everything else working: with `normalized=True` the scores must stay
   within the tolerances the project encodes in its own tests, and the
   default iterative `nx.hits` must be untouched. The project's own test
   files under `networkx/algorithms/link_analysis/tests/` must pass.
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

1. **Reproduce** with the snippet above (scratch files in `/tmp`, never
   inside `/app/src`).
2. **Localise**: read the HITS source. The warning points at the division
   that blows up; study how the eigenvector is selected and where the
   `max()`-based scaling happens. Understand *why* an eigenvector returned
   by `eigh` can have a vanishing largest component before you patch.
3. **Fix** with the smallest possible change, re-run the reproduction, then
   run the project's own tests for the module:
   `python -m pytest networkx/algorithms/link_analysis/tests/test_hits.py -q`
   — they pass on the pristine tree and must keep passing after your fix (the
   grader additionally plants an upstream regression test that this tree does
   not contain yet).
4. Sanity-check other graphs from the same family on your fixed tree, e.g.
   `nx.path_graph(5)` and `nx.path_graph(8)`, for finite non-negative scores.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`; upstream added it with the fix, so it does not
  exist in this tree) into the test file and run the whole link-analysis
  test directory — the regression test must pass and the project's other
  tests must stay green;
- run **hidden cases** — other graphs that reach the same broken scaling
  path (paths of other lengths, a disconnected union) — and require finite,
  non-negative scores equal to the sign-canonicalized dominant-eigenvector
  normalization, with no divide-by-zero warning.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.