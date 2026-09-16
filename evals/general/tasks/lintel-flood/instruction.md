# lintel-flood — repair the floodgate crate

You are a maintainer of **floodgate**, the in-memory rate-limiting library at
`/app/floodgate/`. It is a Rust crate (edition 2021, rustc 1.75) with three
accounting strategies selected through Cargo features:

| Feature combination          | Active strategy                    |
|------------------------------|------------------------------------|
| (default, no features)       | fixed-window counter               |
| `--features sliding`         | sliding-window                     |
| `--features bucket`          | token bucket                       |
| `--features sliding,bucket`  | combined sliding + bucket          |

The crate builds cleanly and its test suite passes under three of the four
combinations. Under the remaining one — `cargo build --features sliding,bucket`
— the build fails with an unresolved-field error wall inside the
combined-strategy integration code. That integration path has never been
brought up to the current strategy APIs: it was written against an older
verdict shape that no longer exists, and it embeds behaviour that contradicts
the crate's own documented contract.

Your job: diagnose the failure, repair the crate so that **all four
combinations** build and pass, and keep the shipped behavioural suite green
under every one of them. The verifier will run `cargo build` and `cargo test`
for each combination inside `/app/floodgate/`, and it will inject additional
integration tests that must pass as well.

## Environment

- `rustc`/`cargo` 1.75 and `gcc` are installed. There is **no network** at
  trial time; this crate has no external dependencies, so everything you need
  is on disk.
- The crate ships at `/app/floodgate/` with its source, its documentation
  (`README.md`), and its unit tests under `tests/`. The tests are the
  specification of the required behaviour. `README.md` documents the exact
  behavioural contract of every strategy, including the combined one — read
  it before you change anything.
- Do not modify anything outside `/app/floodgate/`. Never touch `/tests`.

## How to reproduce the failure

```bash
cd /app/floodgate
cargo build --features sliding,bucket     # fails
cargo test  --features sliding,bucket     # likewise

cargo build                               # the other three combinations pass
cargo build --features sliding
cargo build --features bucket
```

## Constraints

- **Do not remove, rename, or otherwise empty the `sliding` and `bucket`
  features** in `Cargo.toml`, and do not change the default feature set. The
  four-combination matrix above is part of the crate's contract.
- **Do not delete, comment out, or weaken any test in `tests/`.** The suite
  must stay green and complete under all four combinations.
- Keep the public API of the crate source-compatible: the `Config`,
  `Verdict`/`Defer { retry_after_ms }`, and `FloodGate::check(
  key, qty, now_ms)` shapes used by the documentation and tests must remain
  exactly as documented.
- The crate may not use `unsafe`.
- A fix that merely makes `sliding,bucket` compile is not enough: the repair
  must implement the combined strategy's documented contract, otherwise the
  specification tests (and the verifier's injected integration tests) fail.

## Deliverable

The repaired crate **`/app/floodgate/`** — all four feature combinations
green, suite intact, contract honoured. Work inside the crate, and leave the
repository in its fixed state when you finish.

## Reading order (suggested)

1. `README.md` — the contract, including the combined strategy's retry rule.
2. The `tests/` directory — what each strategy must actually do.
3. The failing `sliding,bucket` build — the diagnostics point at the
   integration code that needs repair; the two strategy modules define the
   current verdict shape the integration was written against.