# stem-sloop

You are working inside a real open-source codebase: **Google Guava** (the
`google/guava` library), checked out at a pinned historical commit in
`/app/src` (detached head, working tree starts clean). There is a defect in
this tree's graph API. Your job is to find it, fix it in the working tree,
and prove the fix with the project's own test tooling. You are deliberately
**not** told which class or file to change: localising the bug is part of
the task.

## Environment

- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, reset, rebase, stash or otherwise modify `.git`** — the working
  tree is detached at the pinned commit and must stay exactly there. Only
  the working-tree contents may change.
- **JDK 21** (`javac`/`java`) and `git` are installed. All needed jars are
  already in `/opt/jars` (annotation jars that guava 2022-era sources need
  to compile, plus junit / hamcrest / truth for the project's own tests).
  `/app/README-BUILD.md` has the exact compile and test commands.
- `cpus = 1`: one vCPU. A full `javac` of `guava/src` takes about 7
  seconds, so iterate freely.
- There is **no build output inside `/app/src`**: compile everything into
  `/tmp` (or another scratch directory outside the tree). Any stray file
  you leave inside `/app/src` is flagged by the grader.
- The project's own graph test suite is self-contained (it only uses local
  in-memory graphs and the shipped jars).

## The bug (user-visible symptom)

Guava's graph API distinguishes *ordered* and *unordered* endpoint pairs.
`EndpointPair.ordered(a, b)` represents a directed pair `a -> b`;
`EndpointPair.unordered(a, b)` represents an undirected pair `a - b`
(with `unordered(a, b)` equal to `unordered(b, a)`).

Both pair kinds can be constructed freely and passed to the API. A directed
graph is documented to accept only ordered pairs, and an undirected graph
only unordered pairs; the wrong kind is supposed to be rejected with an
`IllegalArgumentException` (this is what `GraphBuilder.directed()` /
`GraphBuilder.undirected()` users rely on).

On this tree, **undirected** graphs silently accept **ordered** pairs, and
the result is a set that violates the standard `java.util.Collection`
contract. Concretely, with an undirected graph:

```java
MutableGraph<Integer> g = GraphBuilder.undirected().build();
g.putEdge(1, 2);
Set<EndpointPair<Integer>> edges = g.edges();
EndpointPair<Integer> ordered = EndpointPair.ordered(1, 2);

boolean c = edges.contains(ordered);          // reports true ...
boolean any = false;
for (EndpointPair<Integer> e : edges)         // ... but NO element of the
  if (e.equals(ordered)) any = true;          //     set equals that pair

// c == true while any == false  ->  Collection.contains() is lying to you
```

`Collection.contains(x)` is contractually "true iff this collection
contains at least one element e such that x.equals(e)". Here the set
**claims** to contain the ordered pair while no actual member equals it, so
any code that relies on `contains()` to mean "an equal element is present"
breaks: iterating the set to find the matching pair finds nothing, and
`getOrDefault`-style lookups through the set disagree with iterating it.
The same defect is reachable on the undirected graph's **value** variant
(edges with attached values), on undirected **networks** (edges with
explicit identity objects), and on **immutable** undirected graphs, always
in the same shape: a *contains-family* call reports `true` (or returns a
value) for an ordered pair, while iteration shows no equal member.

The behavior is also asymmetric, which is a good clue: on **directed**
graphs the wrong pair kind is rejected loudly, but on **undirected** graphs
the wrong kind slips through and produces exactly these false-positive
membership results.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `CLASSES_DIR` naming a
     directory that contains a compiled `com/google/common/graph` package
     (plus the rest of guava it depends on):
     * if `CLASSES_DIR` is **set**, use those classes exactly as given;
     * if it is **unset**, compile `/app/src/guava/src` yourself into a
       fresh scratch directory under `/tmp` and use that.
   - It must, inside a fresh scratch directory under `/tmp`:
     * write the Java driver it needs (its own small `.java` program),
     * `javac` that driver against the chosen classes, and
     * run it with `java`.
     Never rely on precompiled helper programs.
   - The Java driver must build an **undirected** mutable graph in the way
     shown above (`GraphBuilder.undirected().build()`, `putEdge(1, 2)`),
     compute `c = edges().contains(EndpointPair.ordered(1, 2))`, compute
     `any = (∃ element e of edges() with e.equals(ordered))`, print both
     booleans and a verdict line, and **exit 0 if and only if the
     Collection contract holds** (`c == any`), non-zero otherwise.
   - Print to stdout everything your driver prints, and nothing else (no
     stray authorship banners).
   - It must work no matter what the current working directory is when it
     is invoked, and it must not touch anything outside its scratch
     directory (trap `EXIT` to delete it).

   On the **unfixed** tree this script must fail: the contract is violated,
   so it exits non-zero with the violation printed. Confirm that now,
   before fixing anything.

2. **Fix the tree.** Make the smallest possible consistent change so that
   `/app/repro.sh` passes, and so that an undirected graph rejects an
   ordered pair with `IllegalArgumentException` in the same ways a directed
   graph already rejects an unordered pair. Fix the mechanism, not just one
   input: the same defect is reachable on value graphs, networks and
   immutable undirected graphs (see Grading), so a fix that only patches
   one variant will not pass. Do **not** merely special-case your
   reproduction in a wrapper — the graded checks exercise the code path
   directly through fresh compiles of the tree.

3. **Break nothing else.** Everything else must keep working exactly as
   before: directed graphs must still accept ordered pairs and reject
   unordered ones; undirected graphs must still accept unordered pairs;
   all the previously-existing graph behaviour (edge sets, mutators,
   lookups, adjacency, element order) must be unchanged. The project's own
   test suite must stay green.

4. **Keep the diff minimal.** The grader compares every file's bytes
   against the pinned commit's own blobs; only the source file(s) the bug
   actually lives in may differ, and no files may be added, moved, deleted
   or renamed. If you create scratch files to investigate (including any
   compiled output), delete them before you finish. Your two authored files
   `/app/repro.sh` and `/app/summary.md` live **outside** `/app/src` and
   are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was
   (with the contract explained in your own words), what you changed (which
   classes/logic and why that is the right layer), and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the compile recipe from `/app/README-BUILD.md`
   (`CLASSES_DIR` unset, so your script compiles the tree itself). Observe
   `contains=true` while iteration finds no equal member. Try the directed
   variant (`GraphBuilder.directed()`) with `EndpointPair.unordered(...)`
   to see the asymmetry the undirected case should be mirroring.
2. **Localise** by reading the code. Follow where an `EndpointPair` is
   validated when it enters the graph/network machinery — the pair-kind
   compatibility decision is made in the graph package's shared
   implementations and is what lets ordered pairs through on undirected
   graphs (and, if you look, the mismatch message itself is worded as if
   only directed graphs could ever be offended). Understand *why* the
   check is wrong before you patch it.
3. **Fix** with the smallest possible change, recompile, and confirm
   `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own graph JUnit suite,
   e.g.
   `java -cp "/opt/jars/*:/tmp/classes:/tmp/testlib:/tmp/gtests" org.junit.runner.JUnitCore com.google.common.graph.EndpointPairTest
   com.google.common.graph.StandardMutableUndirectedGraphTest
   com.google.common.graph.StandardMutableDirectedGraphTest
   com.google.common.graph.StandardMutableUndirectedNetworkTest
   com.google.common.graph.ValueGraphTest`
   (see `/app/README-BUILD.md` for a complete list). It prints
   `OK (N tests)` when green.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned commit, that the upstream fix
  commit is **not** reachable from this clone, and that every tracked file
  except the source file(s) the bug lives in is byte-identical to that
  commit (any other modification, added file or stray untracked file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and
  obey their contracts;
- compile `guava/src` **freshly** from your tree into a clean directory and
  run your `/app/repro.sh` against that compile (it must pass) **and**
  against a pristine pre-fix compile of the same tree baked into the image
  (it must fail — proving the symptom is real and your reproduction
  targets it);
- plant the project's **own regression tests** for this bug (the upstream
  test methods added/rewritten with the fix, baked into the image — they do
  not exist in this tree) over the tree's test files, then run them
  method-by-method and as whole classes against your fresh compile: the
  seven methods `endpointPair_undirected_contains`,
  `hasEdgeConnecting_undirected_mismatch`,
  `edgeValueOrDefault_undirected_mismatch`,
  `putEdgeValue_undirected_orderMismatch`, `hasEdgeConnecting_mismatch`,
  `edgesConnecting_orderMismatch`, `edgeConnectingOrNull_orderMismatch`
  must all pass;
- run the project's own existing graph JUnit suite (about twenty classes,
  including the mutable/immutable graph, network, value-graph, traverser
  and equivalence tests) and require it to pass;
- run authored hidden cases that exercise the same code path from inputs
  the upstream tests do not use (a value graph keyed by `String` nodes with
  values attached, a network with explicit edge objects, and an immutable
  graph, plus a directed-graph regression check), each compiled against
  your fresh compile and executed.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.