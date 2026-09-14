# ropewalk-passage

You are working inside a real upstream open-source project: **starship** — the
cross-shell prompt — checked out at a pinned commit in `/app/src` (the working
tree starts clean). The project builds with cargo and Rust 1.98.1 on `PATH`.
There is a bug in this tree's terminal-layout logic. Your job is to find it,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file, function or module to
change: localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency; always build with
  `--locked`.
- **No outbound network.** Everything needed is baked in: the crates.io
  dependency cache and a warm `target/` build directory (all dependencies, the
  `starship` debug binary and the unit-test harness were compiled at image
  build time). Any `cargo` command completes offline; cargo is configured to
  fail closed rather than wait on the network.
- `cpus = 1`: one vCPU. Do not launch parallel builds; cargo will use the
  single core. An incremental rebuild after a one-file edit is well under a
  minute here — budget for it.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

`starship explain` prints a breakdown of everything rendered into your prompt.
Each module row is laid out as three columns:

```
 "{module value}" ({duration})  -  {description}
```

The module-value column (the quoted, possibly colored value) is padded with
spaces so that the `-  {description}` parts line up into one straight column
across all rows.

When a module's value contains **ANSI color escape sequences** — for example a
custom command whose output carries its own color codes, or any module segment
that embeds non-printing escape sequences — the padding is wrong: the column
padding math treats the escape sequence's bytes as if they were printable
characters and gives the value a phantom extra width, so the row is padded with
too few spaces and the description column no longer lines up with the rows
whose values have no color codes. The more escape codes a value carries, the
further that row's description drifts left of the shared column.

## Requirements

1. **Write a failing reproduction first, as a deliverable.** Before changing
   any behaviour, add an inline unit test to the **same source file that
   contains the width measurement the explain layout relies on** (you must
   localise that file yourself from the symptom): a self-contained `#[test]`
   function named `repro_ansi_width_<something>` (the prefix
   `repro_ansi_width_` is mandatory) that asserts that a string literal
   containing ANSI color escape codes measures its **visible** width — i.e.
   the escape sequences are not counted as printed columns. For example, a
   function whose visible text is `normal text` preceded by a magenta color
   code must measure 11 columns. The test must **fail on the untouched tree**
   and pass after your fix. Keep it self-contained: a single test function,
   no helpers, no other files — it must compile unchanged against the
   pristine tree. This test is a graded deliverable: the verifier runs it
   against the pre-fix code (it must fail there) and against your fixed tree
   (it must pass).
2. **Fix the measurement** so that ANSI color escape sequences no longer
   inflate the measured width of a value, without changing how any plain-text
   width is measured. Non-color escape sequences and every other behaviour of
   the project must be unaffected.
3. Everything else must keep working exactly as before: the project's own
   grapheme/width unit tests (`cargo test --locked --offline -- width`) must
   pass on your fixed tree, and the rendered prompt must be unchanged for
   values without color codes.
4. The graded tree must be byte-identical to the original except for the
   source changes the fix requires. Do not add, move, delete, rename or
   reformat any file; if you create scratch files to investigate, delete them
   before you finish; make no commits. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix and your reproduction test in
   the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce.** See the misalignment yourself: point `starship explain` at a
   configuration whose custom command emits pre-colored output, e.g. a
   `[custom.x]` block with `command = "printf '\\033[35mcolored claim'"`, run
   it as `cd /app/src && STARSHIP_CONFIG=<file> ./target/debug/starship
   explain`, and observe the describe-column drift on colored rows. Note that
   the misalignment is a *width-accounting* defect, so the most direct failing
   reproduction is the width-measurement unit test described in requirement 1.
2. **Study the layout logic.** Grep the source for where the explain breakdown
   computes widths and pads with spaces; trace how a module value's width is
   measured. Every measurement that can see escape sequences is suspect.
3. **Fix** the measurement, then rebuild incrementally and re-check both
   directions: your `repro_ansi_width_*` test must fail on the untouched tree
   and pass on the fixed tree, and a colored value must no longer inflate the
   explain column.
4. Run the project's width-related unit tests (warm, offline):
   `cd /app/src && cargo test --locked --offline -- width`
   — these must pass on your fixed tree.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit and that every tracked
  file except the source surface the fix requires is byte-identical to that
  commit (any modification elsewhere, any added file or untracked scratch
  file fails);
- require `/app/summary.md` and your `repro_ansi_width_*` reproduction test;
- run your reproduction test against the pristine pre-fix code — it must
  fail there — and against your fixed tree — it must pass;
- then, on your fixed tree, run the project's own upstream regression test for
  this bug (an inline unit test from a later revision of the tree, injected by
  the grader from outside the repository) along with additional ANSI-width
  generalization cases the grader injects, and the project's pre-existing
  width-related tests. All must pass on your fixed tree.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.