# Build notes (bosun-fathom)

This image hosts a real upstream checkout (BurntSushi/ripgrep) at `/app/src`:

- Base: bench-base:ubuntu-24.04. Build chain: the standard Debian tooling
  (`build-essential pkg-config git curl ca-certificates`) plus the Rust
  1.98.1 toolchain from the official dist tarball
  (static.rust-lang.org, channel dated 2026-09-03).
- The repository is cloned at build time with `git init` plus a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached at that commit. The object store therefore contains exactly one
  commit.
- The tree is built at the parent commit during image build
  (`cargo build --locked`, debug profile, ~20 s on one core), so the agent's
  own `cargo build --locked` runs are incremental, warm and fully offline.
  Cargo's registry cache lives in `/opt/cargo` (env `CARGO_HOME`).
- The trial must not rely on network access; everything it needs is baked
  in (warm cargo cache, pinned Cargo.lock, warm debug build) and `cpus = 1`.
- `/opt/golden/regression.rs` (the project's own regression-test module at
  the fix commit, which adds the r2944_incorrect_bytes_searched test for the
  defect; extracted through a throwaway clone) and `/opt/prefix/rg` (a
  pristine pre-fix binary) are baked by the build; both are sha256-pinned in
  `/opt/pins` and read-only.
- `/app/src` is writable by root and by uid 1000.