# Build notes (cutwater-swell)

This image hosts a real upstream checkout (BurntSushi/ripgrep) at `/app/src`:

- Base: bench-base:ubuntu-24.04. Build toolchain: Rust 1.98.1 installed from
  the official dist tarball at `/opt/rust` (pinned by URL date 2026-09-03 and
  by `rustc --version` check), plus a minimal C toolchain for linking.
- The repository is cloned at build time with `git init` plus a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached at that commit. The object store therefore contains exactly one
  commit.
- The tree is warm-built at the parent commit during image build: a full
  debug build (`cargo build`) and the component unit suite
  (`cargo test -p grep-regex --lib`, 24 tests) both ran, so the agent's own
  `cargo` runs are incremental and fully offline.
- The trial container has no network and `cpus = 1`; `cargo` is pinned to
  one job (`CARGO_BUILD_JOBS=1`) and to offline mode
  (`CARGO_NET_OFFLINE=true`). The crate cache lives at `/opt/cargo`.
- `/opt/prefix/rg` (a pristine pre-fix binary of the pinned commit) and
  `/opt/golden/case_insensitive_alternation.rs` (the project's own regression
  test for the defect, extracted from upstream's fix through a throwaway
  clone) are baked by the build; both are sha256-pinned in `/opt/pins` and
  read-only.
- `/app/src` is writable by root and by uid 1000.

Nothing in this file describes the defect under test; that is in
`instruction.md` and in the task contract.