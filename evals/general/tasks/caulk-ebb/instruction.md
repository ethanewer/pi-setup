# geometric_soft_configuration_graph mishandles a degree dictionary

## Situation

`/app/src` is a shallow, pinned working clone of the NetworkX repository
(`https://github.com/networkx/networkx`), installed from that tree in editable
(development) mode, so `import networkx` gives you exactly the checked-out
source. Python 3.12, `pytest` and the project's own test dependencies are
installed. The image already contains everything you need; there is no
guaranteed network at trial time, so do not attempt to download anything.

## The bug (as a user would hit it)

`networkx.geometric_soft_configuration_graph(beta=..., kappas=...)` generates
a geometric soft configuration graph from a hidden degree sequence. The
documentation describes `kappas` as a dictionary of node-to-degree pairs (a node keyed to its hidden degree value). The mapping form is broken:

- When the node labels are strings, calling the function with your mapping
  raises `TypeError: unsupported operand type(s) for +: 'int' and 'str'` and
  no graph is produced.
- When the node labels happen to be integers, the call does not raise — but
  the returned graph behaves as though the node labels *were* the degrees:
  with large integer labels the graph comes out nearly empty, and the
  per-node radial layout attribute is plainly wrong, even though the degrees
  you supplied are ordinary small numbers.

Both symptoms share one origin: a single miscalculation inside the generator,
in the code that derives the mean hidden degree from a mapping.

## What you need to do

1. **Write your own failing reproduction first** — before changing any code —
   as the deliverable script `/app/reproduce_failure.py`. It must exercise
   `geometric_soft_configuration_graph` with a mapping-form `kappas` argument
   and demonstrate the broken behaviour: the script must fail (nonzero exit)
   when run against the tree as it currently is, and succeed (exit 0) once
   the generator is fixed. Cover the string-label crash; if you can, also
   cover the silent integer-label misbehaviour. Keep it self-contained:
   `import networkx`, build the mapping, call the function, assert on the
   result. The verifier runs this script twice, against pristine copies of
   the generator source and against your fixed tree, so a script that always
   exits 0 (or never exits 0) fails the task.
2. Find and fix the miscalculation in place in the checked-out tree at
   `/app/src`. After your fix:

   - a mapping of string node labels to degrees constructs a valid graph and
     the mean hidden degree is computed from the degree **values**;
   - a mapping whose integer node labels are unrelated to the degrees
     produces exactly the graph those degrees imply — same edge structure,
     same radial layout as the same degrees under any labels;
   - every other behaviour of the generator, for any other input form, is
     unchanged.

3. Drive your work with the project's own test runner from `/app/src`. The
   generator's own test module is
   `networkx/generators/tests/test_geometric.py` (54 tests plus the
   generator's other suites, sub-second to a few seconds at 1 CPU):

   ```
   cd /app/src
   python3 -m pytest networkx/generators/tests/test_geometric.py -q -p no:cacheprovider
   ```

   Add or adjust tests for your own verification as you wish — the working
   tree's tracked files are checked, so keep any scratch files out of the
   repository (or delete them before finishing).

## Constraints

- Deliverables: the repaired tree at `/app/src` and the reproduction script
  `/app/reproduce_failure.py`.
- Change only what the fix requires. Do not rewrite history, add remotes,
  fetch, merge, rebase, stash, commit, or reinstall anything. Do not delete
  tracked files. Do not modify test files, configuration files or build
  files. The only tracked file that may be modified is the generator's own
  source module (a source fix; test or configuration edits will fail
  verification), and at least one such source modification must be present.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them.

## What the verifier checks

In order: the tree is still at the pinned commit with exactly one commit
object, the upstream fix commit is not reachable anywhere in the clone, no
history was fetched, nothing was deleted, only the one allowed tracked source
file is modified, no untracked importable files exist inside the repository,
no interpreter-hook shims exist anywhere (`/app` must hold only your
deliverable, `site-packages` must still match its build-time manifest,
`PYTHON*` environment variables are ignored), and `import networkx` still
resolves to the `/app/src` checkout. Then it runs your reproduction
`/app/reproduce_failure.py` against a pristine copy of the generator source
(expects a failure) and against your fixed tree (expects success), runs the
project's own regression test for this behaviour (taken from upstream, kept
out of the tree at `/opt/golden`, copied in at verification time), re-runs
the generator's own test module, and runs hidden cases over mapping shapes
the upstream regression test does not use.

Deliverables: `/app/reproduce_failure.py` and the repaired `/app/src` tree.