# bosun-fathom

You are working inside a real open-source codebase: **ripgrep** (the
recursive line-oriented search tool, `BurntSushi/ripgrep`), checked out at a
pinned historical commit in `/app/src` (the working tree starts clean and
warm-built). There is a bug in this tree's search statistics. Your job is to
find it, fix it in the working tree, and prove the fix with the project's
own test tooling and a reproduction you write yourself. You are deliberately
**not** told which file or function to change: localising the bug is part of
the task.

## Environment

- The tree lives at `/app/src`. It has been built once with
  `cargo build --locked` (debug profile); the built binary is
  `/app/src/target/debug/rg` and the build is **warm**, so rebuilds after
  edits are incremental and take seconds.
- Rust 1.98.1 is installed and on `PATH`. Cargo's registry cache lives in
  `/opt/cargo` (the `CARGO_HOME` environment variable) — do not delete it.
- `cpus = 1`: one vCPU. Prefer incremental `cargo build --locked` builds.
- **Do not rely on any network.** Everything this task needs is already
  baked into the image: the warm cargo cache (`/opt/cargo`, `CARGO_HOME`),
  the pinned `Cargo.lock`, and the fully built tree. A rebuild is offline.
  Do not attempt to download anything, and in particular never run
  `cargo update`: the committed `Cargo.lock` pins every crate and `--locked`
  must keep working.
- `/app/src` is writable by you, but **do not commit, fetch, push, rebase or
  otherwise modify `.git`** — the working tree is detached at the pinned
  commit and must stay there.
- `/opt/prefix/rg` is a pristine binary built from **this exact tree** as it
  ships (i.e. before any fix). Compare against it at any time.

## The bug (user-visible symptom)

`ripgrep` can report how much work a search did. Run a search with the
`--stats` flag and, at the end of its output, you get a block of counters:
how many matches there were, how many bytes were printed, how many bytes
were searched, and timings. When a search is allowed to run to completion
these numbers are consistent and sensible.

On this tree, however, there is a specific way to search that makes the
counters contradict what actually happened. When the search stops early
because of a maximum-match-count limit — the `-m <n>` / `--max-count <n>`
option, i.e. "stop after n matches" — the stats block reports **zero bytes
searched**, even though the command plainly read data from the file and even
printed the matching lines. The other counters are right: the number of
matches, matched lines and bytes printed all reflect the run, only "bytes
searched" is reported as 0. Running the same search without the early-stop
limit reports a correct non-zero "bytes searched" value, so the statistics
silently contradict what actually happened.

The affected behaviour is: a search that stops early because of a
max-count limit must report, in its `--stats` block, a **non-zero "bytes
searched" number that matches the data actually read** — exactly the way
the same search reports it when it is allowed to run to completion. On this
tree, the wrong counter appears for a specific way of invoking the
early-stop option. You will need to discover for yourself which inputs
trigger it and what the correct figure is: build a small fixture (a few
short lines), search it with `--stats` and with and without a max-count
limit, and compare the two stats blocks. Try varying the shape of the
search — for instance whether the positional path names a file or a
directory — and find the shape where the counter goes wrong.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `RG_BIN` naming the ripgrep
     binary to execute, defaulting to `/app/src/target/debug/rg` when
     unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`
     and run the affected command exactly: a `--stats` search with a
     max-count limit against data of the agent's own choosing, in the
     search form you established, from your own experiments, to trigger
     the wrong counter.
   - It must **derive the expected byte count from its own fixture data**
     (e.g. from how many bytes of the file the early-stopped run must have
     consumed), not from a hardcoded number detached from that data. The
     fixture itself is your choice; keep it small.
   - It prints everything ripgrep prints — stdout and stderr — and nothing
     else.
   - It exits 0 if and only if ripgrep exited 0 **and** the stats block
     contains the correct number of matches **and** reports the expected
     non-zero "bytes searched" value for the fixture; it exits non-zero
     (printing ripgrep's output, which will show the wrong counter)
     otherwise.
   - It must work no matter what the current working directory is when it
     is invoked, and it must not touch anything outside its scratch
     directory.

   On the **unfixed** tree this script must fail: because the early-stopped
   run reports `0 bytes searched` instead of the true figure for your
   fixture, `/app/repro.sh` exits non-zero. Confirm that now, before
   fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0, correct "bytes searched" in the stats
   block), also after a fresh `cargo build --locked`. Fix the mechanism,
   not just one input: the same defect is reachable with any max-count
   value, any number of files, and files with different line lengths and
   line endings (see Grading). Do not merely special-case your
   reproduction in a wrapper script — the graded checks exercise the
   search machinery directly through the rebuilt binary.

3. **Break nothing else.** Everything else must keep working exactly as
   before: plain searches, searches without early-stop limits (whose byte
   counters are already correct), and the other stats figures. The
   project's own test suite must stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `Cargo.toml`, `Cargo.lock`, or any other file. The grader compares every
   file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail. Your two authored files `/app/repro.sh` and
   `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce.** Use `/app/src/target/debug/rg` from a scratch directory
   in `/tmp` (never inside `/app/src`): make a small file with a few short
   lines, search it with `--stats` under a max-count limit that stops the
   search early, and read the stats block. Compare it against the same
   search without a limit, try several input shapes (naming a file vs.
   naming a directory; larger counts that do not stop early; different
   line sizes), and pin down precisely which input shape corrupts the
   counter and what the correct figure for your fixture is. Confirm the
   wrong figure against `/opt/prefix/rg` too, so you are sure you are
   seeing the bug in the tree as shipped and not something else.
2. **Localise** the bug by reading the code. Trace where the "bytes
   searched" figure comes from and where the early-stop decision happens;
   understand *why* the early-stopped run loses its byte accounting while
   the completed run does not, before you patch.
3. **Fix** with the smallest possible change in that one source file,
   rebuild (`cargo build --locked`), and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own test machinery, for
   example the searcher crate's unit suite (`cargo test -p grep-searcher`)
   and the integration suite (`cargo test --test integration`, which runs
   the search-through-the-binary tests; a few hundred tests take about 15
   seconds here), and require them to pass.
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
- force a relink from your tree (the existing binary is thrown away, the
  bug's source file is touched, and `cargo build --locked` rebuilds
  offline, so nothing you planted under `target/` survives) and run your
  `/app/repro.sh` against that repaired binary (it must pass) **and**
  against a pristine pre-fix `rg` binary baked into the image at
  `/opt/prefix/rg` (it must fail — proving the symptom is real and your
  reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) into the tree's regression-test module, run that
  whole module plus the full integration suite, and require the new test
  and every pre-existing test in it to pass;
- run the searcher crate's own unit test suite and require it to pass;
- run authored hidden CLI cases exercising the same code path from inputs
  the upstream regression test does not use (multiple files searched
  together, UTF-8 multibyte lines, and CRLF line endings), each asserting
  an exact "bytes searched" figure against the rebuilt binary.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.