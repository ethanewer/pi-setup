# Task: repair vocabulary memory-zone cleanup in spaCy

## What you are given

You are working with a real checkout of **spaCy** (version 3.8.11, a widely
used NLP library) at `/app/src`. The checkout is a clean, detached clone of a
specific historical commit of the upstream repository. git is available, the
tree is writable, and there is **no network access** in this container — any
fetch, `pip install`, or download will fail, so everything you need is already
on the machine.

The cloud environment installed the checkout itself (`pip install -e .`), so
`import spacy` resolves to `/app/src/spacy` from anywhere. Python is 3.12.13;
numpy 2.5.3, pytest, hypothesis and the project's full dependency closure are
preinstalled.

spaCy's core data structures are written in **Cython** (`.pyx` files). Some
spaCy modules are compiled extension modules (`.so` files built in place under
`/app/src/spacy/`). **If you edit any `.pyx` source file you must recompile the
affected extension modules before the change takes effect**: run
`python3 setup.py build_ext --inplace` from `/app/src` (build-essential is
installed). If behaviour ever looks stale after an edit, delete the stale
`spacy/*.so` files (or the module's `.so`) first, then rebuild; the build
system will regenerate what it needs. Recompiling from scratch takes a couple
of minutes on one CPU; incremental rebuilds of changed modules take seconds.

## The symptom (user report)

spaCy 3.8 introduced a "memory zone" feature for services that process large
volumes of text under a memory budget. Entering a memory zone — via the
`memory_zone()` context manager available on the vocabulary object (and on the
`StringStore` it uses) — makes vocabulary creation transient: any new word
added to the vocabulary while the zone is active is allocated in a temporary
pool and is freed when the zone is exited normally. The vocabulary object also
exposes an `in_memory_zone` property reporting whether a zone is currently
active.

Users report the following bug:

> If an exception is raised inside the `with` block, the vocabulary is left in
> a broken state. When we catch the exception and continue, `in_memory_zone`
> **still reports `True`**, even though the zone's `with` block has fully
> unwound. Words that were created during the failed block are not freed, and
> the vocabulary keeps writing new entries to the temporary memory area, so
> memory usage grows without bound and lookups behave inconsistently. Any
> server that catches errors around a memory zone is left with a corrupted
> vocabulary.

The expected behaviour: no matter how the `with` block exits — normally or via
an exception — leaving the zone must restore the vocabulary to its normal,
non-transient state, free the words that were created inside the zone, and
leave the vocabulary fully usable (old entries intact, new entries
non-transient).

## What the bug is NOT

There is no problem with the feature's normal path: entering a zone, adding
words, and exiting normally works correctly. Do not change the public API
signatures, and do not alter the normal-exit behaviour. The defect is
specifically about what happens *between* the exception and the cleanup.

## Your job

1. **Reproduce it first.** Write your own standalone reproduction of the
   reported bug as `/app/repro.py`. It must:
   - be a self-contained Python 3 script (imports allowed from the installed
     packages only; **no** access to `/tests`, `/solution`, `/opt`, or the
     git history),
   - demonstrably **fail (nonzero exit)** when run against a vocabulary that
     still has the bug, i.e. against the checkout as it is *now*, before you
     fix anything, and
   - **pass (exit 0)** after the bug is fixed,
   - print a clear one-line diagnosis naming the memory-zone symptom when it
     detects the broken state.
   Do **not** fix anything until this reproduction fails against the current
   checkout exactly as reported.

2. **Fix the bug.** Make the reported symptom disappear by changing the
   checkout under `/app/src` (recompile as needed). You may only modify the
   source files that are actually part of the bug; do not change build files,
   tests, configuration, or any unrelated module. Do not add new files under
   `/app/src`. Your fix must keep every existing behaviour working: the normal
   memory-zone path, the rest of the vocabulary/string-store tests, and the
   installed pipeline functionality.

3. **Verify and document.** Your `/app/repro.py` must now exit 0. Run a
   relevant slice of the project's own test suite with pytest (it is all
   installed and offline) to convince yourself nothing else broke. Then write
   `/app/summary.md` (plain Markdown, a few paragraphs) explaining the root
   cause and your fix — what exactly was wrong with the exception path and why
   your change restores correct behaviour.

## Constraints

- Only the two deliverables below plus the fixed sources; do **not** modify
  anything outside `/app/src`, `/app/repro.py` and `/app/summary.md`.
- Do not install, uninstall or upgrade any Python package.
- Do not touch `/opt`, `/tests`, `/solution`, or any file outside `/app`.
- Do not fetch from the network (it will fail anyway).
- The repository must stay at its pinned commit: do not `git commit`, add
  remotes, or otherwise move `HEAD`.

## Deliverables

- `/app/src` — the fixed checkout (recompiled state is fine; the verifier
  rebuilds changed modules from your sources before testing).
- `/app/repro.py` — your own reproduction: fails before the fix, passes after
  it, prints a memory-zone diagnosis on the failing state.
- `/app/summary.md` — root cause and fix write-up.

The verifier will (a) rebuild your changed modules from source and run your
`/app/repro.py` against the repaired tree — it must pass; (b) rebuild an
unmodified copy of the original tree and run your `/app/repro.py` against it —
it must **fail** with the memory-zone diagnosis, proving your reproduction is
real; (c) run the project's own regression test for this bug (from the fixed
upstream commit) plus a slice of the project's existing suite; and (d) run
hidden end-to-end cases of its own on the same code path. It will also verify
that no file outside the bug's actual source files differs from the original
commit.