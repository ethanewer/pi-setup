# cutwater-swell

You are working inside a real open-source codebase: **ripgrep**
(`BurntSushi/ripgrep`), the line-oriented search tool, checked out at a
pinned historical commit in `/app/src` (clean working tree, already built).
There is a bug in this tree's search behaviour. Your job is to find it, fix
it in the working tree, and prove the fix with a reproduction you write
yourself plus the project's own test tooling. You are deliberately **not**
told which component or file to change: localising the bug is part of the
task.

## Environment

- The ripgrep source tree lives at `/app/src`, detached at the pinned
  commit. The working tree is clean. **Do not commit, fetch, push, rebase,
  tag or otherwise modify `.git`** — the tree must stay at the pinned
  commit, and there is no network anyway.
- The tree is **warm-built**: `/app/src/target/debug/rg` exists and works.
  Rust 1.98.1 is installed at `/opt/rust/bin` (already on `PATH`). After
  you edit a source file, an incremental `cargo build` recompiles only what
  changed (seconds to a minute). A full `cargo clean && cargo build` from
  scratch takes a couple of minutes. `cargo` runs with `CARGO_NET_OFFLINE`
  set: every crate the project needs is already cached in `/opt/cargo`, so
  builds never touch the network, even in offline mode.
- `cpus = 1`: one vCPU. `cargo` is pinned to one job (`CARGO_BUILD_JOBS=1`).
- There is **no network** in this container. Everything needed is baked in.
- `rg --trace` runs any search with extensive internal diagnostics printed
  to stderr, showing what ripgrep decided about your pattern before
  searching. It is often the fastest way to see where a search decision
  goes wrong, and it requires the debug build (which you have). Run e.g.
  `rg --trace '<pattern>' <file>` and study the output.
- The project's own unit suite for the component that decides how patterns
  are searched is: `cargo test -p grep-regex --lib` (currently 24 tests,
  all passing). That is the suite you are expected to keep green.

## The bug (user-visible symptom)

ripgrep normally prints every line that a pattern matches. For **certain
patterns** this tree silently misses matches: lines that unambiguously
satisfy the pattern are not printed, with **no error or warning anywhere**.
When *all* matching lines are dropped the command exits with status 1
("no matches"); when only *some* are dropped it exits 0, so the missed
matches leave no trace and are easy to overlook.

The trigger involves patterns that combine the **case-insensitive flag**
(`(?i:...)`) with an **alternation** where at least one alternative
contains a wildcard (`.`). The canonical example: a file whose only line is

```
e-x
```

searched with

```
rg '(?i:e.x|ex)' file
```

prints nothing and exits 1, even though `(?i:e.x|ex)` obviously matches
`e-x` (the `e.x` alternative: `e`, then any one character, then `x`). The
very same pattern *does* find the line `ex` in a file; it is `e-x`-style
lines that disappear. On a file containing both `e-x` and `ex`, only the
`ex` line is printed and the exit status is 0.

The defect is reachable with other spellings of the same idea — for
example `(?i:k.k|kk)` against `k-k`, or `(?i:e..x|ex)` against `e--x` (the
wildcard branch with a longer gap) — and the missed text may appear in any
case (`E-x`, `e-X`) or mid-line (`xx e-x yy`). It does **not** trigger on
every pattern: for many similar-looking patterns the search happens to be
correct. A correct fix must make the missed lines appear without changing
any unrelated search behaviour.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom above. Its contract:

   - It must honour an environment variable `RG_BIN` naming the ripgrep
     binary to execute, defaulting to `/app/src/target/debug/rg` when
     unset.
   - It must create its input in a fresh scratch directory under `/tmp` (a
     text file containing one or more lines that the buggy search drops),
     then run the affected search exactly — one `"$RG_BIN"` invocation with
     a triggering pattern and the input file path as its argument.
   - It prints everything ripgrep prints (stdout and stderr), and nothing
     else.
   - It exits 0 if and only if every line the pattern must match is present
     in the output; it exits non-zero (still printing ripgrep's output)
     otherwise.
   - It must work no matter what the current working directory is when it
     is invoked, and it must not touch anything outside its scratch
     directory.

   On the **unfixed** tree this script must fail: the affected lines are
   missing from the output. Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes. Fix the mechanism, not just one input: the same
   defect is reachable with other alphabets (`(?i:k.k|kk)`), other gap
   widths (`(?i:e..x|ex)`), any casing of the text, matches mid-line, and
   `rg -c` counting (see Grading). Do not merely special-case one pattern
   in a wrapper script — the graded checks exercise the search code path
   directly through the built binary.

3. **Break nothing else.** Everything else must keep working exactly as
   before: plain searches, case-sensitive alternations, patterns that were
   correct before the fix must stay correct, and the project's own test
   suite must stay green:
   `cargo test -p grep-regex --lib` and a fresh `cargo build` must both
   pass. Note: some of the project's own unit-test expectations encode the
   *pre-fix* behaviour of the code you will change; where a fix changes
   what the code produces, expectations that encode the old (buggy)
   behaviour must be updated to the corrected behaviour so the suite stays
   green.

4. **The graded tree must be byte-identical to the pinned commit except
   for the single source file where the bug lives.** Do not add, move,
   delete or rename any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify other
   crates, `tests/`, manifests, lockfile or any other file. The grader
   compares every tracked file's bytes against the pinned commit's own
   blobs, so cosmetic side-changes also fail. Your two authored files
   `/app/repro.sh` and `/app/summary.md` live **outside** `/app/src` and
   are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it (reproduction before and
   after, tests run).

## Recommended working loop

1. **Reproduce** with `/app/src/target/debug/rg` exactly as described
   (scratch files under `/tmp`, never inside `/app/src`). Observe the
   missing output and the exit statuses. Try the sibling variants
   (different letters, different cases, `e--x`, `rg -c`, mid-line text)
   and note which ones trigger the symptom and which do not — that
   contrast is a strong clue about what the search's decision depends on.
   Confirm `/app/repro.sh` fails before you touch any source.
2. **Localise**: find where ripgrep decides, per candidate line, whether a
   pattern can possibly match — including the *pre-search* decision that
   can short-circuit whole files. `rg --trace` shows your pattern's
   compiled search plan; study the code that built it. Ask yourself what
   set of "must-appear" strings is derived from `(?i:e.x|ex)` and why it
   rejects `e-x`.
3. **Fix** the decision so the set derived from the pattern admits every
   string the pattern itself matches. Rebuild, re-run `/app/repro.sh`
   (must now pass), and re-run the project's suite.
4. Re-check the trigger variants from step 1 — they must all now match.
   Write `/app/summary.md`.

## Grading (what the verifier checks)

- `/app/repro.sh` exists, is executable, and exits 0 against your rebuilt
  tree; the same script must **fail** against a pristine pre-fix binary of
  the pinned commit (baked into the image), proving the reproduction
  targets the real symptom.
- The tree is rebuilt from scratch (`cargo clean && cargo build`) and the
  executed binary is that rebuild; the fixed tree must compile cleanly.
- Provenance and scope: `HEAD` still the pinned commit, the upstream fix
  commit not present in the object store, and every tracked file except
  the one where the bug lives byte-identical to the pinned commit.
- The project's own regression test for this bug (which you do **not**
  have — it is planted by the verifier, extracted from the upstream fix)
  is run and must pass, as must the full `cargo test -p grep-regex --lib`
  suite.
- Three hidden CLI cases exercise the same code path from inputs the
  regression test does not use.