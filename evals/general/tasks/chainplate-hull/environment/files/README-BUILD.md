# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (starship, the
cross-shell prompt) checked out at a pinned, shallow (single) commit.
Everything needed to build and test it offline is baked into this image:

- Rust toolchain 1.98.1 on `PATH` (`cargo`, `rustc`, `git`).
- The crates.io dependency cache and a warm `target/` directory: the whole
  workspace, the `starship` binary (`target/debug/starship`) and the test
  harness were compiled at image build time at this same commit.
- `cpus = 1`: one vCPU. Do not launch parallel builds.

Common commands (all offline):

    cd /app/src
    cargo build --locked        # incremental rebuild of target/debug/starship
    cargo test --no-run --locked  # compile (not run) the project's test harness
    cargo test --locked -- <name-filter>  # run unit tests matching the filter

The prompt engine is under `src/formatter/`. The project's own unit tests are
inline `#[cfg(test)] mod tests` blocks inside the source files.

Do not modify the `.git` directory (its history is intentionally shallow),
and do not commit, fetch or pull.