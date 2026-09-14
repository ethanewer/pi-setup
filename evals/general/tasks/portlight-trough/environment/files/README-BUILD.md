# portlight-trough build notes

You are inside a container with a **real, complete checkout** of the **serde**
serialization framework at a pinned historical commit, located at `/app/src`.
This is the actual upstream project — read its code, build it, and test it.

## Toolchain

- Rust **1.70.0** (via rustup) is on `PATH`. You do **not** need to install anything.
- The container has **no network**. Do not try to download crates or run
  `cargo update`. All dependencies this workspace needs are already in the
  offline cargo registry cache, so ordinary `cargo build` / `cargo test` work.
- `CARGO_NET_OFFLINE=true` is set so cargo fails fast instead of hanging.

## The workspace layout

```
/app/src
  serde/                 the core library crate
  serde_derive/          the #[derive(Serialize, Deserialize)] proc-macro crate
  serde_test/            a helper crate for testing serializers with a Token DSL
  test_suite/            the project's own integration test suite
    tests/test_macros.rs   contains the tests for derive attributes incl. the
                           adjacently-tagged-enum tests
```

## Build and test

From `/app/src`:

```sh
cargo build -p serde -p serde_derive -p serde_test
cargo test -p serde_test_suite --test test_macros
```

To run a single test:

```sh
cargo test -p serde_test_suite --test test_macros -- <test_name>
```

A full cold rebuild of the needed crates takes roughly 15-40 seconds; you can
just rebuild after each edit (`cargo test` recompiles only what changed).

## Writing an integration test (for your reproduction)

`serde_test` (already a dev-dependency of the test suite) provides a
`Token`-stream DSL and helpers `assert_de_tokens`, `assert_de_tokens_error`.
Integration tests live under `test_suite/tests/` and are auto-discovered by
cargo. Look at `test_suite/tests/test_macros.rs` for the idiom, including how
adjacently tagged enums are declared with `#[serde(tag = "...", content = "...")]`
and how a token stream is written.

A new file placed at `test_suite/tests/anything.rs` is compiled and run as its
own test binary via `cargo test -p serde_test_suite --test anything`.

## Git hygiene

`target/` and `Cargo.lock` are git-ignored. `.git` is present so you can inspect
the tree (`git log`, `git status`). The tree is currently a detached checkout of
the pinned commit. You may commit nothing; the verifier inspects the working
tree contents.
