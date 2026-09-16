# Working environment

- This is the **rust-lang/regex** workspace, version 1.9.6, checked out at a
  pinned historical commit in `/app/src` (detached `HEAD`). `.git` must not be
  modified in any way (no commits, fetches, pulls, pushes, rebases).
- Rust toolchain **1.98.1** is installed under `/opt` and on `PATH` via
  `RUSTUP_HOME=/opt/rustup` and `CARGO_HOME=/opt/cargo`. `CARGO_NETWORK_OFFLINE=true`
  is set: there is no network, all dependencies are already in the cargo cache
  and pinned by the generated `Cargo.lock` (which is gitignored, as upstream
  expects).
- The workspace build is **warm**: `cargo build` and the repository's own test
  target `cargo test --no-run --test integration` were already run at image
  build time for you, on one CPU (`-j1`). Incremental rebuilds after editing a
  source file take seconds. Prefer `-j1` to keep memory bounded.
- The repository's own test harness is data-driven. `tests/lib.rs` (the
  `integration` test target) embeds every `testdata/*.toml` file at compile
  time and runs each `[[test]]` entry through the suite functions
  (`suite_string`, `suite_bytes`, `suite_string_set`, `suite_bytes_set`,
  plus the `regression`, `misc`, `replace` and fuzz groups). Each entry looks
  like:

  ```toml
  [[test]]
  name = "a-name"
  regex = 'a+'
  haystack = "aaa"
  matches = [[0, 3]]
  ```

  `regex` is a TOML **single-quoted** literal string, so backslashes are
  taken literally; `matches` lists the byte spans `[start, end)` of every
  match `find_iter` must report. The `REGEX_TEST` environment variable
  whitelists cases by substring of their full name (`group/name/expansion`):
  `REGEX_TEST=my-case cargo test --test integration`. The harness prints
  `test result: ok` when the selected cases pass and exits non-zero otherwise.