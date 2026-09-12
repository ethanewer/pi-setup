# bracket-forge build notes

This directory is intentionally near-empty: the task's whole world is the
real `rust-lang/regex` tree that `environment/Dockerfile` clones (shallow,
pinned to parent commit 5ea3eb1e95f0338e283f5f0b4681f0891a1cd836). Nothing
upstream is vendored into this task tree.

The Dockerfile only adds the build's *toolchain* (rustup line 1.98.1, under
/opt — read-only at trial time), warms the crates.io dependency cache and the
`target/` build directory as uid 1000 (writing the uncommitted `Cargo.lock`
that pins today's crates.io state), extracts the upstream regression test for
this bug from the fix commit into `/opt/golden` (via a throwaway clone that is
deleted immediately, so the fix commit is never reachable from `/app/src`),
and fixes ownership so the trial can run as root or uid 1000.

The upstream regression test lives at
`/opt/golden/regression.rs`
(`regex-automata/tests/dfa/onepass/regression.rs` at the fix commit); the
author's hidden generalization cases live under `tests/hidden/` in the task
tree and are planted into `regex-automata/tests/dfa/onepass/` by the
verifier.