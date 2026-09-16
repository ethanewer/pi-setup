# ballast-anchorage

You are working inside a real open-source codebase: **ripgrep**
(`BurntSushi/ripgrep`), a line-oriented text search tool, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's search-and-replace machinery. Your job is to find it, fix it
in the working tree, and prove the fix with the project's own test tooling.
You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed and on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency — do **not**
  run `cargo update` or change the lockfile.
- **There is no network** in this container. Everything needed is baked in:
  the crates.io dependency cache and a warm `target/` build directory (the
  whole workspace, the `rg` binary and the test harness were compiled at
  image build time at this same commit). Any `cargo` command you run
  completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

Combining multiline mode with a replacement string can crash the program
outright. Specifically, when you search with `-U/--multiline` together with
`-r/--replace`, and the pattern uses look-around so that a line yields many
small matches, ripgrep aborts with a Rust panic about an invalid slice index
and exits non-zero instead of printing the replaced lines. Plain text files
with several short matches on a line trigger it, and the crash also occurs
in release builds.

Reproduce it:

```bash
cd /app/src
cargo build      # debug binary (the image already warmed this build)

printf ' b b b b b b b b\nc\n' > /tmp/haystack
./target/debug/rg '(^|[^a-z])((([a-z]+)?)\s)?b(\s([a-z]+)?)($|[^a-z])' /tmp/haystack -U -rx
echo "exit=$?"
```

On the buggy tree this prints a message like

```
thread 'main' panicked at <file>:579:22: slice index starts at 18 but ends at 17
```

(your own reproduction prints the real file:line — that backtrace is the
intended localisation hint) and `exit=101`, with no useful output. The
correct behaviour is to print the replaced lines (`xbxbx`) and exit 0.

## Requirements

1. Fix the tree so that the reproduction above prints exactly `xbxbx` (with a
   trailing newline) and exits 0, in both `cargo build` (debug) and
   `cargo build --release` builds. The same input/pattern, run before your
   fix, dies with the slice-index panic; after your fix it must complete.
2. The crash is a symptom: the underlying defect is that a replace pass can
   end a match *past* the end of the search range it was given. Fix the
   mechanism, not just this one input — the same bug is reachable from other
   inputs and patterns (see Grading). Do not merely add a guard in `main` or
   wrap the call in a panic handler.
3. Everything else must keep working exactly as before: plain (non-multiline)
   search, ordinary replacement with capture groups, `--only-matching`,
   multiline search without replacement, and non-replacing output must all be
   unchanged. The project's existing test suite must stay green.
4. The graded tree must be byte-identical to the pinned commit except for the
   **single source file where the bug lives** (the one named by the panic
   backtrace). Do not add, move, delete, rename or reformat any file; if you
   create scratch files to investigate, delete them before you finish; make
   no commits; do not modify `tests/`, `Cargo.toml`, `Cargo.lock` or any
   metadata file. The grader compares every file's bytes against the pinned
   commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `cargo build` and the one-liner above (scratch files in
   `/tmp`, never inside `/app/src`).
2. **Localise** the bug: read the panic backtrace, then study the function it
   names, including how `last_match`, `range.end` and `bytes.len()` interact
   when matches come from a pattern with look-around in multiline mode.
   Understand *why* the slice can be inverted before you patch.
3. **Fix** with the smallest possible change in that one file, rebuild
   (`cargo build`), and confirm the reproduction prints `xbxbx` with exit 0.
4. **Prove nothing else broke**: the project's own test harness lives in
   `tests/` and is compiled with `cargo test --no-run`; the resulting
   executable is `target/debug/deps/integration-*` (new cargo layout places
   test binaries under `target/debug/deps/`). Run a targeted subset by
   passing plain filter arguments, e.g.
   `ls -t target/debug/deps/integration-* | grep -v '\.d$' | head -1` then
   `"$BIN" r1311_multi_line_term_replace misc::replace misc::replace_groups multiline::overlap1 multiline::context`
   — every one of these passes on the pristine tree and must still pass
   after your fix, and the harness runs the adjacent `target/debug/rg`
   itself. Also run the reproduction in a `cargo build --release` build.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) into `tests/regression.rs`, rebuild the harness
  offline, and run it: the planted regression test must pass, and a selection
  of the project's existing multiline/replace integration tests must still
  pass;
- run `target/debug/rg` directly on **hidden CLI cases** — other files and
  patterns that reach the same broken code path and must now print the
  expected replaced output with exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.