# Build notes (alewife-anchorage)

This image hosts a real upstream checkout at `/app/src`:

- Base: bench-base:ubuntu-24.04.
- Rust toolchain 1.98.1 installed via rustup from sh.rustup.rs into
  `/opt/rustup` / `/opt/cargo` (on PATH at build and trial time).
- The repository is cloned at build time with `git init` + a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached. `Cargo.lock` pins every crate version; do not run
  `cargo update`.
- The whole workspace, the `rg` debug binary and the test harness are
  compiled at image build time (warm `target/`), so all `cargo` commands
  run offline during the trial.
- The trial container has no network and `cpus = 1`.
- `/opt/golden/regression.rs` and `/opt/prefix/rg` are baked by the build;
  both are sha256-pinned in `/opt/pins` and read-only.

Nothing in this file describes the defect under test; that is in
`instruction.md` and in the task contract.