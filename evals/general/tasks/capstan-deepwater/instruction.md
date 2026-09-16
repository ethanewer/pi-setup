# capstan-deepwater

You are working inside a real open-source codebase: **ripgrep**
(`BurntSushi/ripgrep`), a line-oriented text search tool, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's glob/path filtering. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed and on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency — do **not**
  run `cargo update` or change the lockfile.
- **There is no network** in this container. Everything needed is baked in:
  the crates.io dependency cache and a warm `target/` build directory (the
  whole workspace, the `rg` binary at `target/debug/rg` and the test harness
  were compiled at image build time at this same commit). Any `cargo` command
  you run completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

Glob filters — the `-g/--glob` option — whose **final path component ends
with a dot** are silently ignored: ripgrep acts as if the glob does not
exist. Reproduce it:

```bash
cd /app/src
cargo build      # debug binary (the image already warmed this build)

mkdir -p /tmp/t/asdf /tmp/t/asdf.      # note the directory named "asdf."
touch /tmp/t/asdf/foo /tmp/t/asdf./foo

cd /tmp/t && /app/src/target/debug/rg --files -g '!asdf./'
```

On the buggy tree this prints **both** `asdf./foo` and `asdf/foo`: the
negation glob meant to exclude the directory `asdf.` (a directory whose name
ends in a dot, spelled with a trailing `./` in the glob) excludes nothing.
The correct output is exactly `asdf/foo`. For comparison, the same tree with
`-g '!asdf/'` (excluding the plain directory `asdf`) works correctly and
prints exactly `asdf./foo`.

The defect is not specific to that one command. Any glob whose final path
component ends with a dot silently stops working:

- a **negated** glob meant to exclude such a path excludes nothing — the
  path still shows up in `--files` output and in search results;
- an **included** glob meant to select such a path selects nothing at all
  (no output, exit status 1).

The trailing-dot name may be a directory or a plain file, may be nested
(e.g. a directory `a/bb.` excluded with `-g '!**/bb./'`, or a file `x.`
excluded with `-g '!x.'`), and may end in several dots (e.g. `one..`); all
of those stop working the same way.

## Requirements

1. Fix the tree so that globs whose final component ends in a dot behave
   exactly like any other glob. With the reproduction above,
   `rg --files -g '!asdf./'` (run from inside the fixture directory) must
   print exactly `asdf/foo`; a
   negated glob must exclude the named file or directory (and, for a
   directory, everything under it); an included glob must select it, and
   search results must be filtered correctly as well.
2. The symptom above is the visible part: fix the **mechanism**, not just
   this one input. The underlying defect is that the path handler which
   extracts the final "file name" component of a path — the component used
   by glob matching to compare against the glob's own final component —
   drops the name as soon as a path ends in a dot, even though a trailing
   dot is a perfectly ordinary character in a Unix file name. Fix that
   handler in the single file where it lives. Do not special-case the
   reproduction, and do not merely add a workaround at the call sites.
3. Everything else must keep working exactly as before: `--files` with
   ordinary globs, negations like `-g '!*.rs'`, extension globs,
   case-insensitive globs, and `.gitignore`-style matching must be
   unchanged. The project's own test suite must stay green.
4. The graded tree must be byte-identical to the pinned commit except for
   the **single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `Cargo.toml`, `Cargo.lock` or any metadata file. The grader compares
   every file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `cargo build` and the commands above (scratch files in
   `/tmp`, never inside `/app/src`). Try the other variants too — a plain
   file with a trailing-dot name, a nested trailing-dot directory with a
   `**/`-prefixed glob, an inclusion glob — until you can see the shape of
   the failure: matching "acts as if the name did not exist".
2. **Localise** the bug: study how ripgrep matches command-line globs
   against candidate paths. Matching compares the final "file name" portion
   of the candidate path with the glob's own final component, and ripgrep
   uses optimisations that key off that extracted name (and the extension
   derived from it). Find where that final component is extracted from a
   path and what happens there when the path ends in a dot. Understand why
   a trailing dot is special-cased there and why that special case is wrong
   before you patch.
3. **Fix** with the smallest possible change in that one file, rebuild
   (`cargo build`), and confirm every reproduction from step 1 now behaves
   correctly (and that paths ending in `..` still have no file name, as the
   Rust standard library's `file_name` documents).
4. **Prove nothing else broke**: the project's own test harness lives in
   `tests/` and is compiled with `cargo test --no-run`; the resulting test
   executable is under `target/debug/deps/` (`integration-*`). Run a
   targeted subset, e.g.:

   ```bash
   BIN=$(ls -t target/debug/deps/integration-* | grep -v '\.d$' | head -1)
   "$BIN" --test-threads 1 misc::glob misc::glob_negate misc::glob_case_insensitive \
          misc::glob_case_sensitive misc::glob_always_case_insensitive \
          misc::include_zero misc::include_zero_override misc::preprocessing_glob
   ```

   Every one of these passes on the pristine tree and must still pass after
   your fix.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- rebuild the debug `rg` binary and the project's own test harness from your
  tree, offline;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) into `tests/regression.rs`, rebuild the harness, and
  run it: it must pass, and the glob integration tests selected above must
  still pass;
- run `target/debug/rg` directly on **hidden CLI cases** — other files and
  globs that reach the same broken path: negated and included globs on
  trailing-dot file names, a `**/`-prefixed negation over a nested
  trailing-dot directory, and a search-mode run over a tree containing a
  trailing-dot directory — each must print the byte-exact expected output
  and exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.