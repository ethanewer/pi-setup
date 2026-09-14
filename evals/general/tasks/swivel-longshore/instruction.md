# swivel-longshore

You are working inside a real open-source library: **NetworkX**
(`networkx/networkx`), the Python package for graph algorithms, checked out
at a pinned historical commit in `/app/src`. The tree is installed editable,
so any change you make under `/app/src/networkx/` takes effect immediately:
`import networkx` picks it up with no reinstall step. There is a bug in this
tree's group betweenness centrality computation. Find it, fix it, and prove
the fix.

## Environment

- `/app/src` is the full real upstream tree, detached at exactly one pinned
  commit. It is writable. **Do not** run any git command that changes the
  repository's history or refs — no commits, no fetch, no rebase, no reset,
  no `checkout` of another commit. Your fix is made in the working files and
  left uncommitted.
- There is **no network** in the trial container; everything needed is
  baked into the image.
- `cpus = 1`. The relevant test suites are light (a few seconds) — just do
  not parallelize your own runs.
- `python3 -m pytest ...` works. numpy and pandas are installed; the target
  code path itself needs none of them.
- `/app` is writable; your deliverables go there.

## The bug (user-visible symptom)

`networkx.group_betweenness_centrality(G, C, ...)` measures how much a
group of nodes `C` lies on the shortest paths of a graph: for every pair of
nodes **outside** `C`, it counts the fraction of the shortest paths between
that pair that pass through some vertex of `C`, and sums those fractions
(that is the documented definition in the function's own docstring).

Users report two wrong behaviours on this tree, both easy to hit on small
connected undirected unweighted graphs of 6–10 nodes:

1. The function returns a **non-zero** value for a group `C` even though
   **no shortest path between any two nodes outside `C` has an interior
   node in `C`**. The mathematically correct value is 0 — if no path
   between any eligible pair passes through the group, there is nothing to
   contribute. Reported values are small rationals like 0.125 = 1/8 or
   even 1/9, so they are not floating-point noise; they are spurious
   contributions.
2. For a single-node group `{v}`, group betweenness must equal ordinary
   per-node betweenness centrality (no group of size 1 can behave
   differently from the node it contains), and on this tree the two can
   disagree.

The affected function is deterministic and pure Python — there is no
randomness, no data download, no external service involved.

## Your job

Do this in order.

### 1. Write a failing reproduction first

Create `/app/repro.py`, a self-contained Python script (executable,
shebang line included) that demonstrates symptom 1: a graph and a group
for which the shipped tree computes a mathematically wrong non-zero group
betweenness. Its contract:

- It must honour the environment variable `NX_PACKAGE_ROOT`. When that
  variable is set to a non-empty value, the script must insert it at the
  front of `sys.path` **before importing networkx**, so `import networkx`
  resolves to the copy found at that path; when it is unset, it must import
  the installed package normally. No other variable is consulted.
- It builds its own **connected, undirected, unweighted** graph with at
  least 6 nodes and a group `C` of **2 or 3 nodes**, chosen — by you, by
  experimentation against the shipped tree — so that the shipped tree
  computes a value that is wrong (a short-path/pass-through analysis shows
  the true value; any pair of non-group nodes with a shortest path through
  the group's interior would be a legitimate contribution, so pick a graph
  where there are none and the true value is 0).
- It computes exactly one centrality value:
  `gbc = networkx.group_betweenness_centrality(G, C, normalized=False)`
  with no other centrality calls and no other arguments changed.
- It prints **exactly one line to stdout**: `GBC=<value>` where `<value>` is
  the float returned, and nothing else on stdout.
- It exits 0 if and only if that value equals the mathematically correct
  value for the graph/group it chose (within `1e-9`); it exits non-zero
  otherwise.
- It works no matter what the current working directory is.
- It reads nothing under `/opt` or `/tests` and hard-codes no file paths
  other than the documented `NX_PACKAGE_ROOT` behaviour.

Iterate on it until running it against the installed (shipped) tree exits
**non-zero for the right reason**: it prints a `GBC=` value that is not the
mathematically correct one. That is your written proof the bug is real.

### 2. Find the defect

Read the implementation of the function you just exercised. Understand what
each variable means — in particular the difference between "all shortest
paths between two nodes" and "shortest paths that stay within the group's
own path-count tables" (the tables that account for which nodes lie in the
group). Make the **minimal change** so that the value is correct according
to the documented definition: both symptoms above must disappear, and every
existing project test must keep passing. This is a pure localisation-and-
one-line-correction task; the change you need is tiny once you see it, but
the reasoning to get there is the task.

### 3. Prove the work

Create `/app/summary.md` — a short markdown report containing:

- the root cause: which source file and function, what the erroneous
  expression computes instead of what the definition requires, and the
  exact defect expression (before and after, one expression each);
- why symptom 1 and symptom 2 are the same defect;
- the verification you ran: `/app/repro.py` failing before your change and
  passing after it, plus the project pytest commands you ran and their
  results.

## Constraints that are enforced by the verifier

- **Scope**: only tracked files may be modified, and **at most one source
  file** under `/app/src/networkx/` may differ in content from the pinned
  commit. The verifier hashes every other tracked file's bytes against the
  pinned commit's blobs, so `git update-index --assume-unchanged` or
  similar tricks will not hide an edit. Untracked files are allowed only if
  git itself ignores them (e.g. `__pycache__`).
- `/app/repro.py` must really target the bug: the verifier runs it against
  a pristine baked copy of the tree where the library still has the bug
  (the copy's location is a per-build random path, disclosed only to the
  verifier; the script must exit **non-zero** there — this proves the
  reproduction detects the defect, and that the defect actually existed),
  and against your repaired tree (it must exit **0**). It also runs it
  against a fresh copy of your repaired tree. Either way, it must behave
  according to the tree it actually imports, not according to any
  hard-coded path.
- `/app/repro.py` must be executable; `/app/summary.md` must be non-empty.
- The verifier then replaces the tree's group-centrality test file with the
  project's **own upstream regression tests for this exact defect**
  (extracted at image build time from the upstream fix; you do not have
  access to them) and requires all of them to pass, then requires the
  project's previously-existing centrality tests to keep passing. Finally,
  it runs hidden generalization cases that compare group betweenness
  against an independent computation on graphs you have not seen —
  including values that are non-zero, so "return 0 for everything" or
  hard-coding one graph is not a passing strategy.

## Scoring

Binary reward, no partial credit: a fix that satisfies everything above
scores 1; anything else scores 0.