# cistern-bight

You are working inside a real upstream open-source library: **clap-rs/clap**, a
command-line argument parser, checked out at a pinned commit in `/app/src`
(the working tree starts clean). There is a bug in this tree's help-text
rendering. Your job is to find it, fix it in the working tree, and prove the
fix with the project's own test tooling. You are deliberately **not** told
which file or function to change: localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed and on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency.
- Outbound network is not guaranteed and must not be relied on. Everything
  needed is baked in: the crates.io dependency cache and a warm `target/`
  build directory (the library plus all test binaries were compiled at image
  build time). Any `cargo` command you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds; cargo will use the
  single core.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

The library decides, per command, whether `-h` / `--help` output uses the
**short, compact layout** (one option per line, e.g.
`  -h, --help  Print help`) or the **long layout** (the option on its own line,
description indented on following lines). Several properties of an argument
can force the long layout — in particular, an argument whose **possible
values** carry description texts (the help text for a possible value is
filled in automatically when you document it).

The bug: an argument whose possible-values list is **hidden from help output**
(`.hide_possible_values(true)`) can still cause that switch. When such an
argument has possible values and any of them carries a description,
`--help` changes from the compact one-line listing to the long layout and
even appends a hint like `(see a summary with '-h')` — even though hiding the
value list is meant precisely to keep help output concise and the hidden list
should not influence the layout at all.

Reproduce it with a scratch program (builder API), e.g.:

```
Command::new("ctest").arg(
    Arg::new("pos")
        .hide_possible_values(true)
        .value_parser([
            PossibleValue::new("fast"),
            PossibleValue::new("slow").help("not as fast"),
        ])
        .action(ArgAction::Set),
)
```

Running `ctest --help` on this program prints `-h, --help` on its own line
with `Print help (see a summary with '-h')` on the next — it must print the
compact `  -h, --help  Print help` instead.

## Requirements

1. Fix the tree so that a **hidden possible-values list** never influences the
   help layout: when the only long-layout triggers belong to arguments whose
   value list is hidden, `-h` and `--help` must render in the short, compact
   layout.
2. Everything else must keep working exactly as before: an argument whose
   possible values are shown and carry help texts (or an argument with a long
   help text) must still select the long layout, with the same texts.
3. The graded tree must be byte-identical to the original except for **the
   single source file where the bug lives**. Do not add, move, delete, rename
   or reformat any file; if you create scratch files to investigate, delete
   them before you finish; make no commits. The grader compares every file's
   bytes against the pinned commit's own blobs, so cosmetic side-changes also
   fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with a scratch program **outside** `/app/src` (a tiny cargo
   project in e.g. `/tmp/repro` with a path dependency on `/app/src`, or a
   scratch `.rs` file you temporarily drop under `tests/builder/` — delete it
   before finishing).
2. **Build the project's own test suite** (warm, offline):
   `cd /app/src && cargo test --no-run -p clap`
   This compiles the library and the trybuild test binaries. To run the
   builder test suite: `BIN=$(ls -t target/debug/deps/builder-* | grep -v '\.d$' | head -1)` then `"$BIN"` (all pass before your change).
   Do NOT run plain `cargo test` executing every target: the `ui`/`derive`/
   `examples` suites are slow at 1 vCPU and are not what the grader runs.
3. **Localise** the layout decision in the source (grepping the builder source
   for the long-help/short-help decision and for `hide_possible_values` /
   `possible values` will find it), apply a minimal fix, and re-run the builder
   suite — it must stay green while your reproduction now prints the compact
   layout.
4. Confirm both directions: arguments with hidden value lists no longer switch
   layouts; visible arguments with helped possible values or long help texts
   still do.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/summary.md` to exist;
- place the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, from a successor revision of the tree) and its own
  hidden tests into `tests/builder`, rebuild offline, and run the entire
  builder test suite. Every suite binary must pass, including that regression
  test and hidden variants: hidden value lists that carry helped possible
  values (`-h` and `--help`), hidden value lists combined with long help texts
  (which must keep the long layout), and visible-argument controls that must
  keep the long layout.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.