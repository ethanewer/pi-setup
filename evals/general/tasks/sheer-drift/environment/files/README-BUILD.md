# Build notes (sheer-drift)

This image hosts a real upstream checkout (`BurntSushi/ripgrep`) at `/app/src`:

- Base: bench-base:ubuntu-24.04. Rust 1.98.1 is installed system-wide from
  the official dist tarball (channel date 2026-09-03); `rustc`/`cargo` are on
  `PATH`.
- The repository is cloned at build time with `git init` plus a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached at that commit. The object store therefore contains exactly one
  commit.
- The tree is built at the parent commit during image build
  (`cargo build --release --locked`), so the agent's own builds are
  incremental and fully offline. Cargo's download cache and index live in
  `/opt/cargo` (`CARGO_HOME`); do not delete it. The committed `Cargo.lock`
  pins every crate; do not run `cargo update`.
- The trial container has no network and `cpus = 1`.
- `/opt/golden/regression.rs` (the project's own regression test for the
  defect, extracted from the fix commit through a throwaway clone) and
  `/opt/prefix/rg` (a pristine pre-fix binary) are baked by the build; both
  are sha256-pinned in `/opt/pins` and read-only.
- `/app/src` is writable by root and by uid 1000.

Nothing in this file describes the defect under test; that is in
`instruction.md` and in the task contract.