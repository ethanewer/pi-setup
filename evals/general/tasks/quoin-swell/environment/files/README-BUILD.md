# Build notes (quoin-swell)

This image hosts a real upstream checkout (sharkdp/fd, the `fd` file finder)
at `/app/src`:

- Base: bench-base:ubuntu-24.04, plus `gcc`, `make`, `curl`, `libc6-dev` and
  a Rust toolchain (rustup stable, minimal profile) installed under
  `/opt/rustup` and `/opt/cargo` (owned by uid 1000).
- The repository is cloned at build time with `git init` plus a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached at that commit. The object store therefore contains exactly one
  commit.
- The tree is built at the parent commit during image build (`cargo build
  -j1`, ~90 seconds on one core), and the integration-test harness is
  pre-compiled (`cargo test --no-run`), so the agent's own builds and test
  runs are incremental and fully offline. `CARGO_NET_OFFLINE=true` is set for
  the whole trial: cargo never touches the network.
- The trial container has no network and `cpus = 1`.
- `/opt/golden/tests.rs` (the project's own regression test for the defect,
  extracted from the fix commit through a throwaway clone that was deleted
  immediately; the fix commit itself is provably unreachable from `/app/src`)
  and `/opt/prefix/fd` (a pristine pre-fix binary) are baked by the build;
  both are sha256-pinned in `/opt/pins` and read-only.
- `/app/src` is writable by root and by uid 1000.

Nothing in this file describes the defect under test; that is in
`instruction.md` and in the task contract.