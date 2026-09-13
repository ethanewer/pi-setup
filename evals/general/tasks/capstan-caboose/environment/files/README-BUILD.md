# capstan-caboose

This image ships a real upstream Rust project checked out at `/app/src`
(pinned, shallow, detached HEAD). The working tree is writable; `.git` must
stay untouched.

Environment notes:

- Rust toolchain 1.98.1 is installed under `/opt` (`cargo`, `rustc`, `git`
  on `PATH`). The toolchain tree is read-only, but the cargo home and the
  warm `target/` build directory under `/app/src` are writable, so every
  `cargo` command completes offline and `--locked` resolves every dependency
  from the warm cache.
- The `starship` debug binary is prebuilt at `/app/src/target/debug/starship`
  and the unit-test harness was compiled at image build time, so the first
  reproduction needs no compilation; only your own edits require an
  incremental rebuild (a few minutes at one vCPU).
- The trial runs with no outbound network and one vCPU. Cargo is configured
  (`CARGO_NET_OFFLINE`) to fail closed on any network attempt.
- Ownership is arranged so the trial works as root or uid 1000. `git` has
  `safe.directory` configured system-wide; do not create commits.
- The grading harness injects its own files at verify time; treat `/tests`
  and `/opt` as opaque.

The task statement — what bug to find and fix, and how to prove it — is in
the trial's instruction file, not here.