# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (ripgrep) checked out
at a pinned, shallow (single) commit. Everything needed to build and test it
offline is baked into this image:

- Rust toolchain 1.98.1 on `PATH` (`cargo`, `rustc`, `git`).
- The crates.io dependency cache and a warm `target/` directory: the whole
  workspace, the `rg` binary (`target/debug/rg`) and the test harness were
  compiled at image build time at this same commit.
- `cpus = 1`: one vCPU. Do not launch parallel builds.

Common commands (all offline):

    cd /app/src
    cargo build                 # incremental rebuild of target/debug/rg
    cargo test --no-run         # compile (not run) the project's test harness
    BIN=$(ls -t target/debug/deps/integration-* | grep -v '\.d$' | head -1)
    "$BIN" --test-threads 1 <filter>   # run a test filter (e.g. misc::glob)

The project's own full test command is `cargo test --all`; at 1 vCPU it is
slow, and only a targeted subset is what the grader runs.

Do not modify the `.git` directory (its history is intentionally shallow),
and do not commit, fetch or pull.