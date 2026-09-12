# bracket-forge

You are working inside a real upstream open-source library: **rust-lang/regex**
(the `regex` crate ecosystem), checked out at a pinned commit in `/app/src`
(the working tree starts clean). There is a bug in this tree's low-level
matching APIs. Your job is to find it, fix it in the working tree, and prove
the fix with the project's own test tooling. You are deliberately **not** told
which file or function to change: localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed and on `PATH` (`cargo`, `rustc`, `git`).
- **There is no network** in this container. Everything needed is baked in:
  the crates.io dependency cache (the warm build wrote a `Cargo.lock` pinning
  today's crate versions) and a warm `target/` build directory (the
  `regex-automata` library plus the `integration` test binary were compiled at
  image build time). Any `cargo` command you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds; cargo will use the
  single core.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.
- `/opt/golden/regression.rs` holds the project's **own regression test** for
  the bug you are about to fix. It was added upstream together with the fix,
  so it does **not** exist in this tree; you may copy it into
  `regex-automata/tests/` to reproduce and to verify (remember to delete any
  file you add and to undo any module wiring before you finish).

## The bug (user-visible symptom)

The crate `regex-automata` exposes low-level, slot-based matching APIs. The
caller supplies a buffer of "slots"; each capture group of the compiled regex
occupies two slots (start index / end index), and the caller may provide
**any** number of slots — more, fewer, or exactly the number the compiled
regex needs. The public API contract says the search must succeed and simply
leave empty the slots it does not need.

That contract is violated by the **one-pass DFA** engine (`dfa::onepass::DFA`,
searched via `try_search_slots` / `try_search_slots_imp` / the captures API).
When the caller provides **more** slots than the compiled regex has groups,
the search panics at runtime with a slice range error instead of returning a
value. Two immediately reproducible shapes are:

- a completely trivial pattern with **zero capture groups**: searching
  `abc` (anchored) with a 4-slot buffer panics;
- a pattern containing a group that is repeated **zero times** — e.g.
  `(abc)(ABC){0}` — whose captures never participate: searching the anchored
  haystack `abcABC` with a 6-slot buffer (fits that never-participating
  group) panics, even though with 4 slots the same search succeeds.

In both cases the search must instead succeed: the overall match offsets must
be written into the first two slots, any participating capture groups must be
filled in, and every leftover slot (whose group never participated, or which
has no group at all) must be left `None`.

Reproduce it with a scratch test module under
`regex-automata/tests/dfa/onepass/` (wire it into
`regex-automata/tests/dfa/onepass/mod.rs`), or by copying the project's own
regression test from `/opt/golden/regression.rs` into that directory and
running it, e.g.:

```
cargo test -p regex-automata --test integration -- dfa::onepass::regression
```

## Requirements

1. Fix the tree so that every slot-based search on the one-pass DFA succeeds
   whenever the caller supplies **more** slots than the compiled regex needs:
   the search returns normally, and the unused trailing slots are left
   `None`. Slots for participating groups must still be filled with the
   correct offsets, and matching must behave exactly as before in every other
   case (including a caller supplying fewer slots than the regex needs, and
   callers supplying exactly the right number).
2. Everything else must keep working exactly as before: the rest of the
   `regex-automata` test suite must stay green.
3. The graded tree must be byte-identical to the original except for **the
   single source file where the bug lives**. Do not add, move, delete, rename
   or reformat any file; if you create scratch test files to investigate,
   delete them and undo any module wiring before you finish; make no commits.
   The grader compares every file's bytes against the pinned commit's own
   blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** by planting the project's own regression test (or your own
   scratch module) under `regex-automata/tests/dfa/onepass/` and running it —
   it panics before the fix, passes after. Delete all scratch additions
   before finishing.
2. **Build the project's own test suite** (warm, offline):
   `cd /app/src && cargo test --no-run -p regex-automata --test integration`
   then run the existing one-pass suite:
   `cargo test -p regex-automata --test integration -- dfa::onepass::suite`
   (all pass before your change; runs in seconds).
3. **Localise** the panic. The panic message (it names the very file and
   source line of the panic, and tells you it is a slice range error) is a
   pointer: read the slot-handling logic where the search sizes its scratch
   space against the caller's slot buffer, and where recorded capture
   offsets are copied back into the caller's slots, and you will find the
   bug. Apply a minimal fix.
4. Confirm both directions: the regression test(s) pass **and** the existing
   one-pass suite stays green.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/summary.md` to exist;
- place the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`) and its own hidden tests into
  `regex-automata/tests/dfa/onepass/`, rebuild offline, and run them together
  with the project's own existing one-pass suite. Every test must pass,
  including regression variants that supply far more slots than the compiled
  regex needs: multi-pattern one-pass searches, patterns with never-
  participating capture groups, plain patterns with no groups, and UTF-8/
  empty-match patterns.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.