# Fix adjacently-tagged enum deserialization with extra map keys

You are working in a real upstream checkout of the **serde** serialization
framework at `/app/src` (a faithful, complete copy of the project at one pinned
historical commit). A Rust 1.70.0 toolchain is installed and all the project's
dependencies are already available offline. Read `/app/README-BUILD.md` for the
exact build and test commands. **The container has no network**: do not add new
crate dependencies or run `cargo update`.

## The behaviour you must fix

serde supports **adjacently tagged enums**: an enum serialized as a single map
that holds exactly two interesting keys — one "tag" key whose value names the
variant, and one "content" key whose value holds the variant's data. This is
declared with derive attributes like:

```rust
#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", content = "data")]
enum Msg { /* variants */ }
```

**User-visible symptom:** deserializing such an enum fails as soon as the
incoming map also contains any other, unrelated key (for example extra metadata
fields emitted by a different writer). Even though unknown fields are silently
ignored everywhere else in serde, when an adjacently tagged enum is involved,
the very first key that is neither the tag nor the content triggers a hard
deserialization error, so a map carrying extra metadata cannot be parsed at all.
The intended behaviour: when the enum does **not** declare
`#[serde(deny_unknown_fields)]`, unrelated keys should be skipped transparently
and the map should still deserialize; when it **does** declare
`#[serde(deny_unknown_fields)]`, such keys should be rejected deliberately with
an error.

## Deliverables

1. **A failing reproduction** at **`/app/repro.rs`** — a single self-contained
   Rust integration-test file. It must:
   - define an adjacently tagged enum via `#[serde(tag = "...", content = "...")]`,
   - deserialize a value of that enum from a map that carries **at least one
     unrelated key** in addition to the tag and content keys,
   - assert the deserialized value is the expected one.
   - It must work as a drop-in integration test:
     `cp /app/repro.rs test_suite/tests/repro_custom.rs && cargo test -p serde_test_suite --test repro_custom`
     must **fail while the bug is present** and **pass once you fix it**. Use the
     `serde_test` crate's `Token` / `assert_de_tokens` helpers, and mirror the
     existing tests under `test_suite/tests/` for the idiom.

2. **A fix to the library** in `/app/src` such that your reproduction passes and
   the project's existing test binaries still pass, and such that
   `deny_unknown_fields` is honoured as described above. The verifier runs the
   project's own regression test for this behaviour and additional hidden cases
   over the same code path, so make the fix general rather than special-cased to
   your reproduction.

3. **`/app/summary.md`** — a concise write-up of the root cause and the change
   you made.

## Constraints

- Modify files under `/app/src` only where a correct fix logically requires it,
  and leave the working tree otherwise clean — no stray untracked files under
  `/app/src`. Do not modify any test file or `serde_test` itself.
- Do not add new crate dependencies (no network).
- Your reproduction itself lives at `/app/repro.rs`, not in the shipped test
  suite.

## How you will be judged

The verifier applies `/app/repro.rs` to both the repaired tree and a pristine
pre-fix copy of `/app/src`, requiring it to pass on the former and to fail on
the latter; it replants the project's own regression test for this behaviour and
runs the project's test binaries; and it runs hidden cases over the same code
path from inputs you have not seen. All of these must pass for a correct fix.
