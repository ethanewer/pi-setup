# dragger-narrows - build notes

The image clones the real upstream repository `astral-sh/uv` at a pinned
parent revision into `/app/src`, installs the toolchain revision pinned by
the repository's own `rust-toolchain.toml` (1.98.1), and pre-builds the
`dev` profile (`cargo build -p uv`) plus the `python` test target
(`cargo test -p uv --test python --no-run`) so the trial works offline
with fast incremental rebuilds.

The trial environment has `cpus = 1`; cargo is pinned to `jobs = 1` via
`/opt/cargo/config.toml` and `CARGO_BUILD_JOBS=1`. The crate dependency
and crates.io registry caches live under `/opt/cargo` and are warm.

There is no guaranteed network at trial time; do not attempt to fetch
anything.