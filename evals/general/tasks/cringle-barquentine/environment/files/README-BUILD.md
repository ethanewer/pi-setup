# Working in /app/src (ripgrep)

This image contains a real upstream checkout of `BurntSushi/ripgrep` (the `rg`
search tool) at a pinned historical commit, already built in release mode.

## Toolchain

- rustc / cargo **1.98.1** from the static.rust-lang.org dist tarball,
  installed at `/opt/rust/bin` (already on `PATH`).
- `CARGO_HOME=/opt/rust` — the dependency registry cache was warmed at image
  build time, and the committed `Cargo.lock` pins every crate. **Do not run
  `cargo update`**; it would try to reach the network and rewrite the lock.
- The release profile has debug info and assertions enabled
  (`[profile.release] debug = 1` in `Cargo.toml`), which is why internal
  `assert!` failures are visible in the release binary.

## Build / test commands (run from /app/src)

```bash
cargo build --release -j1          # incremental; ~1 minute for a clean rebuild
/app/src/target/release/rg --help  # the built binary

cargo test --release -j1           # the project's own integration suite (tests/)
cargo test --release -j1 -p grep-regex -p grep-matcher   # unit tests of the
                                   # two search crates (regex + matcher)
```

The tree is detached at the pinned commit. The `.git` directory must remain
untouched (no commits, no fetch, no reset). The verifier compares every
tracked file's bytes against the pinned commit, so keep the tree clean apart
from the source change your task actually requires.

## No network

Do not expect network access from this container. Everything needed to build
and test is already in the image.