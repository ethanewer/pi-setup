# cistern-bight

This image ships a real upstream Rust command-line-parsing library checked
out at `/app/src` (pinned, shallow, detached HEAD). The working tree is
writable; `.git` must stay untouched.

Environment notes:

- Rust toolchain 1.98.1 is installed under `/opt` (`cargo`, `rustc`, `git`
  on `PATH`). The toolchain tree is read-only, but the cargo home and the
  warm `target/` build directory under `/app/src` are writable, so every
  `cargo` command completes offline.
- The trial runs with no outbound network and one vCPU.
- Ownership is arranged so the trial works as root or uid 1000. `git` has
  `safe.directory` configured system-wide and a build identity set; do not
  create commits.
- The grading harness injects its own files at verify time; treat `/tests`
  and `/opt` as opaque.

The task statement — what bug to find and fix, and how to prove it — is in
the trial's instruction file, not here.