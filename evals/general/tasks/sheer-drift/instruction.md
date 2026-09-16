# sheer-drift

You are working inside a real open-source codebase: **ripgrep** (the
recursive line-oriented search tool, `BurntSushi/ripgrep`), checked out at a
pinned historical commit in `/app/src` (the working tree starts clean and
warm-built). There is a bug in this tree's output-printing machinery. Your
job is to find it, fix it in the working tree, and prove the fix with the
project's own test tooling and a reproduction you write yourself. You are
deliberately **not** told which file or function to change: localising the
bug is part of the task.

## Environment

- The tree lives at `/app/src`. It has been built once with
  `cargo build --release --locked`; the release binary is
  `/app/src/target/release/rg` and the build is **warm**, so rebuilds after
  edits are incremental and quick.
- Rust 1.98.1 is installed and on `PATH`. Cargo's download cache lives in
  `/opt/cargo` (the `CARGO_HOME` environment variable) — do not delete it.
- `cpus = 1`: one vCPU. Prefer incremental `cargo build --release --locked`
  builds; a full clean rebuild takes several minutes.
- **There is no network** in this container. Everything needed is baked in;
  a rebuild is fully offline.
- `/app/src` is writable by you, but **do not commit, fetch, push, rebase or
  otherwise modify `.git`** — the working tree is detached at the pinned
  commit and must stay there.
- `/opt/prefix/rg` is a pristine binary built from **this exact tree** as it
  ships (i.e. before any fix). Compare against it at any time.

## The bug (user-visible symptom)

Searching ordinary files with `ripgrep` while **CRLF line-ending handling is
enabled together with forced color output** makes the program crash when a
**matched line is empty** — that is, when the input contains a line with no
text at all and the search pattern you choose matches it. On this tree, such
a run dies mid-print instead of printing the matching lines:

- the process aborts with a panic — in a release build you see an
  "index out of bounds" panic whose index is a huge unsigned number
  (`18446744073709551615`); in a debug build the same defect shows as
  "attempt to subtract with overflow";
- it exits with a non-zero status (101 in this build);
- **nothing is printed** — the panic happens before the matched line is
  written out.

Inputs whose lines all contain text are unaffected, and so are searches that
omit either `--crlf` or the color flag. To fix the behaviour, you first have
to find an input and a pattern that actually hit it.

The affected behaviour is: searching such an input with `--crlf --color
always` must print every matching line and exit 0 — exactly what the command
does when the input has no empty lines.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `RG_BIN` naming the ripgrep
     binary to execute, defaulting to `/app/src/target/release/rg` when
     unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`,
     with the affected search run with the flags that trigger the crash.
   - It must run the search in the non-recursive form the description
     above calls for (a positional path naming a single file), and print
     everything ripgrep prints — stdout and stderr — and nothing else.
   - It exits 0 if and only if ripgrep exited 0 **and** produced non-empty
     stdout (the matched line(s) actually printed); it exits non-zero
     (printing ripgrep's output, which will show the crash) otherwise.
   - It must work no matter what the current working directory is when it
     is invoked, and it must not touch anything outside its scratch
     directory.

   On the **unfixed** tree this script must fail: the search panics, exits
   non-zero and prints nothing, so `/app/repro.sh` exits non-zero. Confirm
   that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0, non-empty stdout), also after a fresh
   `cargo build --release --locked`. Fix the mechanism, not just one input:
   the same defect is reachable with any number of empty lines, with the
   empty line anywhere in the file, and when the input arrives through a
   file argument **or** through stdin (see Grading). Do not merely
   special-case your reproduction in a wrapper script — the graded checks
   exercise the code path directly.

3. **Break nothing else.** Everything else must keep working exactly as
   before: plain searches, `--color always` without `--crlf`, and `--crlf`
   on files that contain no empty lines. The project's own test suite must
   stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate
   (including core dumps from the crashing binary), delete them before you
   finish; make no commits; do not modify `tests/`, `Cargo.toml`,
   `Cargo.lock`, or any other file. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also
   fail. Your two authored files `/app/repro.sh` and `/app/summary.md` live
   **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src/target/release/rg` exactly as described
   (scratch in `/tmp`, never inside `/app/src`): make a file with one or
   more empty lines, search it with an empty-matching pattern and
   `--crlf --color always`, and observe the panic and exit code 101. Try
   the sibling invocations (no `--crlf`; no color; a file with no empty
   lines) to pin down precisely which input shape crashes.
2. **Localise** the bug by reading the code. The panic message names the
   file and line where the arithmetic went wrong; read that printer code
   and understand *why* an empty matched line ends up computing the index
   that overflows. Understand the CRLF-mode line-terminator trimming logic
   before you patch.
3. **Fix** with the smallest possible change in that one source file,
   rebuild, and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own test machinery, for
   example the printer crate's unit tests (`cargo test --release -p
   grep-printer`) and the regression-search test module
   (`cargo test --release --test integration -- regression`), and require
   them to pass.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream
  fix commit is **not** reachable from this clone, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and
  behave per their contracts;
- force a relink from your tree (it recompiles the changed source file and
  rebuilds the binary; the binary you wrote is thrown away first, so
  nothing you planted under `target/` survives) and run your `/app/repro.sh`
  against that repaired binary (it must pass) **and** against a pristine
  pre-fix `rg` binary baked into the image at `/opt/prefix/rg` (it must
  fail — proving the symptom is real and your reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) into the tree's regression test module, run that whole
  module, and require the new test and every pre-existing test in it to
  pass;
- run the printer crate's own unit test suite and require it to pass;
- run authored hidden CLI cases exercising the same code path from inputs
  the upstream regression test does not use (an empty line in the middle of
  content lines, an all-blank file, the input arriving through stdin rather
  than a file argument, and a real CRLF file with a non-empty match whose
  byte-exact colored output pins the carriage-return trimming behaviour),
  each asserted byte-exact against the rebuilt binary.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.