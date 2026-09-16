# bracket-basin build notes

This directory is intentionally near-empty: the task's whole world is the
real `clap-rs/clap` tree that `environment/Dockerfile` clones (shallow, pinned
to parent commit 62da8f94b9aef9f08679e72190f222c84c974af4). Nothing upstream
is vendored into this task tree.

The Dockerfile only adds the build's *toolchain* (rustup line 1.98.1, under
/opt — read-only at trial time), warms the crates.io dependency cache and the
`target/` build directory as uid 1000, extracts the upstream regression test
for this bug from the fix commit into `/opt/golden` (via a throwaway clone
that is deleted immediately, so the fix commit is never reachable from
`/app/src`), and fixes ownership so the trial can run as root or uid 1000.

The upstream regression test lives at `/opt/golden/hidden_args.rs`; the
author's hidden generalization cases live under `tests/hidden/` in the task
tree and are planted into `tests/builder/` by the verifier.