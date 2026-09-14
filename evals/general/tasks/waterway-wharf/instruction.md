# waterway-wharf

You are working inside a real open-source library: **the Rust `regex` crate
workspace (`rust-lang/regex`)**, version 1.9.6, checked out at a pinned
historical commit in `/app/src`. There is a bug in this tree's search
machinery. Your job is to find it, fix it in the working tree, and prove the
fix with the project's own test tooling. You are deliberately **not** told
which file or function to change: localising the bug is part of the task, and
no reproduction is given — writing your own is your first deliverable.

## Environment

- Foundational facts (toolchain, warm build, the data-driven test harness,
  the `REGEX_TEST` filter): read `/app/README-ENV.md` first.
- Rust toolchain 1.98.1 is on `PATH`. There is **no network**:
  `CARGO_NETWORK_OFFLINE=true`; every dependency is in the warm cargo cache
  and `Cargo.lock` pins the resolution. Build and test with `-j1` (one CPU).
- The workspace is **warm**: `cargo test --no-run --test integration` already
  compiled. After you edit a source file, an incremental rebuild is fast.
- `/app/src` is writable by you. Do **not** commit, fetch, pull, push, rebase
  or otherwise modify `.git`; the working tree is detached at the pinned
  commit and must stay that way.

## The bug (user-visible symptom)

Searching text that **begins with non-ASCII characters**, using a pattern that
**ends with a Unicode word boundary `\b` followed by a literal** (like a
newline), can return a silently wrong answer. Instead of the true match — the
full, valid match that exists at the very start of the haystack, covering the
whole haystack — the search reports a **shorter match that starts late**
(somewhere toward the end of the haystack), and the capture group 0 span is
misaligned with the characters that actually matched. The very same pattern on
ASCII-only haystacks is fine.

The failing shape in detail: a pattern that matches *one or more characters,
then a word boundary, then a newline* (that is `.+` followed by `\b` followed
by `\n`), searched against a haystack like a Greek letter followed by two
digits and a terminating newline (e.g. `β77` plus a newline). The correct
answer for that haystack is **precisely one match spanning the entire
haystack**, starting at the first character; the current tree can instead
report a later, truncated match and misaligned captures. The defect is also
reachable with the same pattern against other non-ASCII-leading haystacks, and
with other trailing literals besides a newline (for example a tab), so a fix
that special-cases one haystack or one terminator is not a fix.

## Your job

1. **Write a failing reproduction first** — `/app/repro.sh` — **before**
   touching any source code. Its contract:

   - an executable shell script, robust to the current working directory it is
     invoked from, touching nothing outside `/app/src` and its own scratch
     space;
   - it appends **its own** `[[test]]` entry to `/app/src/testdata/regression.toml`
     (the file the `regression` group of the project's own harness reads),
     under a name beginning with `ww-repro-`, idempotently: if an entry with
     that name already exists in the file, it must not add a duplicate;
   - the entry asserts the **correct** expectation for the failing shape
     above: the pattern `.+` word-boundary newline (as the TOML single-quoted
     literal `regex = '.+\b\n'`), a haystack fitting the description (leading
     non-ASCII letter, digits, newline), and `matches` equal to one match
     spanning the whole haystack;
   - it then runs the project's own harness filtered to that entry, e.g.
     `REGEX_TEST=ww-repro-<your-name> cargo test --test integration`, and
     prints everything the harness prints;
   - it exits 0 if and only if that run reports the case passed (the harness
     found the full match), and non-zero otherwise.

   On the **unfixed** tree the harness must FAIL your entry (it will report
   the truncated match), so `/app/repro.sh` must exit non-zero. Confirm that
   now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that a rebuild and
   `/app/repro.sh` pass. Fix the mechanism, not one input: the graded checks
   exercise the same code path with line-initial non-ASCII text, with an
   ASCII character before the non-ASCII text, and with a tab terminator
   instead of a newline (see Grading), and with the project's own regression
   test for this bug. Do not merely special-case one input in a wrapper
   script; the graded checks run the project's own harness against the
   compiled tree.

3. **Break nothing else.** The project's own existing tests — the string,
   bytes and set suite functions and the regression group — must stay green
   after the fix.

4. **The graded tree must be byte-identical to the pinned commit except for
   the source file(s) where the bug lives and the data file
   `testdata/regression.toml`** (which your reproduction necessarily edits).
   Do not add, move, delete or rename any other file; make no commits; do not
   modify `tests/`, `Cargo.toml`, or any other file. Delete scratch files you
   create to investigate (core dumps, temporary patches) before you finish.
   The grader compares every tracked file's bytes against the pinned commit's
   own blobs, so cosmetic side-changes also fail.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce.** Read `tests/lib.rs`, `tests/suite_string.rs` and
   `regex-test/lib.rs` to understand the harness, then add your `ww-repro-*`
   entry, run the harness, and watch it fail with the truncated match. Try
   sibling inputs (different non-ASCII-leading haystacks, a tab terminator)
   to pin down which shapes are affected before you change anything.
2. **Localise.** The defect is not in the pattern parser. Trace where a search
   result is produced: for these patterns a literal at the end of the pattern
   lets the engine search efficiently, and something about a word boundary
   adjacent to a non-ASCII character makes it give up partway. Find where and
   why, and what the engine does instead of giving up.
3. **Fix**, rebuild, confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own suite functions, e.g.
   `cargo test --test integration -- suite_string::default`,
   `cargo test --test integration -- suite_bytes::default`,
   `cargo test --test integration -- suite_string_set::default`, and the
   plain `cargo test --test integration`.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier will, on your final tree:

- assert that `HEAD` is still the pinned parent commit and that the upstream
  fix commit is **not** reachable from this clone;
- assert every tracked file except the affected source file(s) and
  `testdata/regression.toml` is byte-identical to the pinned commit, and no
  stray untracked file is left inside `/app/src`;
- revert the affected source file(s) to the pinned blobs, rebuild, and run
  your `/app/repro.sh`: it must **fail** (exit non-zero, with the harness
  reporting the truncated match) — proving the symptom is real in this tree
  and that your reproduction targets it;
- restore your fix, rebuild, and run your `/app/repro.sh`: it must **pass**;
- plant the project's own regression test for this bug (baked into the image
  at `/opt/golden`) into `testdata/regression.toml` and require the full
  integration harness (`cargo test --test integration`) to pass, broken
  nothing else;
- run authored hidden cases exercising the same code path from inputs the
  upstream regression test does not use: a different non-ASCII leading letter,
  an ASCII prefix before the non-ASCII text, and a tab terminator instead of
  the newline.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.