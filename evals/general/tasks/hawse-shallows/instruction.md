# hawse-shallows

You are working inside a real open-source codebase: **Guava** (`google/guava`),
Google's core Java library, checked out at a pinned commit in `/app/src` (the
working tree starts clean at that commit). There is a bug in this tree's
string-splitting machinery. Your job is to find it, fix it in the working tree,
and prove the fix with a reproduction that *you* write, the project's own test
tooling, and your own reasoning. You are deliberately **not** told which file or
function to change: localising the bug is part of the task.

## Environment

- OpenJDK 21 (`javac`, `java`) and `git` are installed and on `PATH`. Maven is
  **not** used: the library compiles with plain `javac` against a small set of
  jars already baked in at `/opt/jars/*` (Guava annotation, test and runtime
  dependencies, all present; no network needed).
- **There is no network** in this container. Everything is already on disk.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is a shallow (single-commit), detached clone. Do
  **not** `git commit`, `git fetch`, `git pull`, or otherwise modify `.git`.
- `/app/README-BUILD.md` has the exact copy-paste compile and test recipes.

## The bug (user-visible symptom)

`Splitter.on(Pattern)` and `Splitter.onPattern(...)` split strings on a
`java.util.regex.Pattern`. When the pattern is capable of matching an *empty*
string — a word boundary (`\b`), a lookahead (`(?=...)`), a lookbehind
(`(?<=...)`), or an alternation containing any of these — the split can
silently **drop the final piece of the input**. The pieces that *are* returned
are all correct and in order; it is as if iteration over the separator matches
stops too early, just before the end of the string, so the last token is lost
without an error.

The affected behaviour shows up in two ways:

- A one-character (or one-word) input that contains only a single token
  surrounded by zero-width matches, e.g. splitting `"f"` on the word-boundary
  pattern `\b`, comes back as an **empty** iterable — the entire input has
  vanished from the result.
- A longer input split on a pattern that matches zero width *between*
  characters (e.g. lookarounds that fire after every occurrence of a letter)
  can lose the **final character**: every token is present except the last one,
  so your program's consumer silently never sees it.

Anything that iterates the result — `Lists.newArrayList(...)`, `Iterables`, a
`for` loop, a join — therefore sees a shorter list than the input warrants.
Nothing throws; nothing prints a warning.

Your task: find the defect, fix it in the working tree, and *prove* it with a
reproduction you write from scratch (no reproduction is provided to you).

## Deliverables

All three are required and are checked by the verifier:

1. **`/app/src`** — the fixed working tree. The bug must be fixed there, using
   only source under `/app/src`; every tracked file except the one(s) you change
   must stay byte-for-byte identical to the pinned commit, and the tree must
   still compile with the recipe in `/app/README-BUILD.md`. Clean up any scratch
   files you create inside the tree.

2. **`/app/repro/SplitRepro.java`** — a single-file, self-checking reproduction
   you author. Contract:
   - Public Guava API only (the split entry points and ordinary collection
     iteration / `Lists.newArrayList`); it must compile with plain `javac`
     against the compiled library classes (recipe in `/app/README-BUILD.md`)
     and against nothing else.
   - It prints the split results it computed (a human-readable line per case is
     enough) and exits **0 if and only if** the split results are the *correct*
     ones. On any incorrect behaviour it must exit non-zero and print a short
     reason to stderr.
   - It must cover the affected behaviour described above — both the
     whole-input-vanishes case and the dropped-last-piece case. The inputs and
     patterns you choose are up to you, but they must be affected by this bug:
     before the fix your program must actually *fail* (exit non-zero), and
     after the fix it must pass.

3. **`/app/summary.md`** — a short engineering note: what the user-visible
   symptom is, where the defect lives (file, class, method), why the code is
   wrong, and what you changed. Do not claim anything you did not verify.

## What correct behaviour looks like

For the affected patterns, the correct result contains every non-empty piece of
the input: a single-word input split on `\b` is a one-element iterable
containing that word, and a string split on zero-width boundaries that match
after every occurrence of some character keeps that character as a piece.
You can sanity-check your expectations for any input with the platform's own
`java.lang.String.split(Pattern)` behaviour, but your reproduction must
exercise Guava's `Splitter` end to end (compile and run against the tree you
are fixing), not re-implement splitting.

## Sequence of work (recommended)

1. Compile the library once (recipe in `/app/README-BUILD.md`).
2. Write a small scratch program that splits candidate inputs on zero-width
   patterns and prints the results. Observe the dropped token yourself.
3. Turn that into `/app/repro/SplitRepro.java` with the exit-code contract
   above, and watch it fail against the un-fixed tree.
4. Localise the defect in the source, fix it, recompile incrementally, and make
   `/app/repro/SplitRepro.java` pass.
5. Run enough of the project's own existing `SplitterTest` methods (see
   `/app/README-BUILD.md`) to be confident nothing else broke.
6. Write `/app/summary.md` and clean the tree.

Do not modify anything under `/opt`, do not touch `.git`, and do not use the
network. The verifier will re-run your reproduction, the project's own
regression test for this bug, a selection of the project's existing tests, and
its own additional cases — make your fix real, not input-specific.