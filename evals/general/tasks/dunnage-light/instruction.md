# Conditional default values are silently ignored

## Situation

`/app/src` is a shallow, pinned clone of the `clap-rs/clap` repository
(`https://github.com/clap-rs/clap`), the Rust command-line argument parsing
library, checked out in detached HEAD at upstream commit
`8bb3853eb5e19e9190d142ebb9ae230312da89f1`. Rust 1.98.1 is installed and the
workspace is **prebuilt**: `target/` is warm and the crate cache is populated,
so everything works entirely **offline**. There is **no network** at trial
time (`git fetch`, `curl`, `cargo add` and any other network use will fail).

The project's own test harness for the builder API lives under `tests/`:

```
cd /app/src
cargo test --no-run -p clap      # compile the harnesses (incremental, ~1 min)
BIN=$(ls -t target/debug/deps/builder-* | grep -v '\.d$' | head -1)
"$BIN"                            # run the whole builder suite (baseline: 1576 passed)
"$BIN" --test <name>              # run one test by name
```

Each test file under `tests/builder/` is a module registered in
`tests/builder/main.rs` with a `mod <name>;` line. Read a few existing tests
there before writing your own: they show the harness's conventions (the test
attribute, `assert!` / `assert_eq!`, `OsStr` values, how a command is built
and matched).

## The bug

The builder API lets you attach a **conditional default value** to an
argument: a value the argument silently takes on at parse time when *another*
argument is present with a specific value. The command still parses either
way — the conditional only decides what the dependent argument reads back.

There is a flavour of that feature that accepts a **whole list of such
conditions in one call**, keyed on the OS-string layer (the names of the
conditions and the default values may be arbitrary bytes, not just UTF-8).
When one of those conditions is written by referring to the condition
argument by its **plain identifier** — the ordinary id string you gave the
argument — the conditional is silently ignored: the CLI parses fine, the
condition argument keeps the value the user typed, but the argument that
should have received the default reports **having no value at all**, exactly
as if the condition had never been registered. The same conditional
registered through the single-condition flavour works, and the same
list-of-conditions flavour over plain (non-OS) strings works, which makes the
failure look data-dependent and hard to diagnose.

The commands below reproduce the shape of the failure: `other` should read
back the default, but reports nothing.

```
my_cargo --flag 标记2        # flag parses to "标记2", other should read "flag=标记2"
```

## What you need to do

**Step 1 — before touching any source code**, add a failing reproduction as
a new test in the project's own harness at exactly this path:

```
/app/src/tests/builder/dunnage_repro.rs
```

It must be a module registered in `tests/builder/main.rs` (a
`mod dunnage_repro;` line, following how the neighbouring modules are
registered), and it must contain a test function named exactly
`default_value_ifs_os_repro`. The test must build a small command with the
affected feature and assert the correct behaviour: when the condition is met,
the dependent argument reads back the conditional default; contents of the
condition argument round-trip; and when the condition is **not** met, the
dependent argument must read back **no value** (a default must not appear
unconditionally).

Build and run it **before changing any source**: the test must FAIL against
the code as shipped (non-zero exit, `FAILED`, assertion `left == right`
failed with `left: None`). You have not finished step 1 until you have seen
it fail.

**Step 2 — fix the bug** in the checkout so that:

1. your reproduction passes,
2. the same list of conditions keyed by plain identifiers now applies,
   without changing the semantics of the working flavours,
3. the whole builder suite stays green (`cargo test --no-run -p clap` then
   run the harness binary with no arguments; it must report 0 failed), and
4. the condition-not-met case still yields no default.

The repaired tree at `/app/src` is the deliverable. Change only what the fix
requires: the source change plus the reproduction test and its one-line
registration. Do not touch `Cargo.toml` / `Cargo.lock`, build files, other
tests, `target/`, or the git history. Do not add remotes, do not fetch, do
not commit.

`/tests` and `/solution` are harness-owned; do not read or modify them.
Anything outside `/app/src` (the `/opt/*` verifier state) is off-limits.

## What the verifier checks

1. The tree is still the pinned clone: HEAD equals the commit above, the
   working tree differs from it **only** in the source fix, the new
   reproduction test, and its registration line, and nothing else changed.
2. Your reproduction test is run against a pristine copy of the *unfixed*
   tree (the verifier's own snapshot): it must FAIL there. Run against your
   repaired tree, it must PASS.
3. The project's own regression test for this bug (added upstream after this
   commit, not present in the checkout) is run against your repaired tree and
   must PASS.
4. Two authored hidden cases exercise the same code path from inputs the
   upstream regression does not use (a multi-condition list whose conditions
   fire in order, including a case where no condition is met; and a condition
   keyed on a short flag), and must PASS.
5. The whole builder suite must report 0 failed.