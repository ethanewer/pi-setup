# A flattened tagged enum makes a tagged struct serialize the wrong tag

## Situation

`/app/src` is a shallow, pinned clone of the serde project
(`https://github.com/serde-rs/serde`), checked out at the pinned upstream
commit `bb99b31eb0a55393101f9c80cd959b3a739ad70f`. It is a Cargo workspace of
several crates: the `serde` runtime library, the `serde_derive`
proc-macro crate that implements `#[derive(Serialize, Deserialize)]`, and
`serde_test` + `test_suite`, the project's own test infrastructure and
integration tests.

Rust 1.88.0 is installed via rustup and is the active toolchain
(`RUSTUP_TOOLCHAIN=1.88.0` is exported in the environment). `cargo` runs
offline (`CARGO_NET_OFFLINE=true`): the crates.io registry cache and a full
warm build of the test-suite binaries are already baked into the image, so
builds work with **no network**. There is **no network** at trial time:
`git fetch`, `curl`, and any download will fail.

The project's own test runner is cargo's, from `/app/src`:

```
cd /app/src
cargo test -p serde_test_suite --test test_macros
```

At the pinned commit this file is green on this toolchain.

## The bug

serde supports an internal representation tag: `#[serde(tag = "...")]` on a
*struct* makes every serialized instance of that struct carry an extra
`"tag" -> TypeName` entry at the start of its serialized map, so a consumer
can tell which type it is. The same attribute on an *enum* (optionally with
`#[serde(content = "...")]`) makes each serialized variant carry its own
tag/name entry.

When a struct that has an internal tag contains a field marked
`#[serde(flatten)]` and that flattened field's type is itself a tagged enum
(internally tagged, or tagged with `tag` plus `content`), serializing the
struct emits the **wrong tag string at the point where the flattened value's
own tag should appear**: the entry that must carry the flattened enum's own
tag/name is written out with the outer struct's tag/name instead, and the
struct's own tag entry is dropped. Data serialized by this combination does
not round-trip: deserializing it produces a different value, and any consumer
that dispatches on the enum's tag misparses the output. Deserialization
itself reads the same tokens back correctly — the defect is in serialization
only.

## Reproducing it

The natural place to reproduce it is the project's own rawest layer: a
struct with an internal tag, a flattened field, and a tagged enum, checked
with the project's own `serde_test` token matcher. Add a test like this one
to `test_suite/tests/test_macros.rs` (the `serde_test` imports it needs are
already at the top of that file):

```rust
#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "tag_struct")]
pub struct Struct {
    #[serde(flatten)]
    pub flat: Enum,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "tag_enum", content = "content")]
pub enum Enum {
    A(u64),
}

#[test]
fn repro_tagged_struct_with_flattened_enum() {
    assert_ser_tokens(
        &Struct { flat: Enum::A(0) },
        &[
            Token::Map { len: None },
            Token::Str("tag_struct"),
            Token::Str("Struct"),
            Token::Str("tag_enum"),
            Token::Str("A"),
            Token::Str("content"),
            Token::U64(0),
            Token::MapEnd,
        ],
    );
}
```

This describes the correct serialized form: the struct's own tag
(`"tag_struct" -> "Struct"`) comes first, then the flattened enum's own tag
entries (`"tag_enum" -> "A"`, `"content" -> 0`). On the current checkout the
assertion panics with a token mismatch, which is the bug.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. every serialized instance of an internally tagged struct carries the
   struct's own tag entry, even when the struct has flattened fields;
2. a flattened tagged enum inside such a struct keeps its own tag entries;
3. a value serialized this way deserializes back to an equal value (the
   stream round-trips).

Drive your work with the project's own test runner (`cargo test -p
serde_test_suite --test test_macros`, optionally with `-- <testname>` to run
one test). The full existing `test_macros` integration suite is green at the
pinned commit; keep it that way. A correct fix requires changing only the
serialization side of the derive code generation; the runtime `serde` crate
and the build configuration do not need to change.

## Constraints

- No network; everything needed is already installed.
- The clone is the deliverable. Change in place only what the fix requires
  and nothing else: no history rewrites, no remotes, no fetches, no new
  files, no build-file changes. A scratch regression test added to
  `test_suite/tests/test_macros.rs` may stay — the verifier runs its own
  copy of that file, so your edits there do not affect the verdict.
- Files under `/opt/golden`, `/opt/harness`, `/tests` and `/solution` are
  harness-owned; do not modify them. `/opt/harness` holds the verifier's
  integrity manifests (hashes of the golden test, the toolchain binaries
  and the crates.io sources); the verifier re-hashes the same files during
  grading and fails on any difference. The verifier's copy of the project's
  test file lives at `/opt/golden/test_macros.rs` (read-only; you can read
  it if useful, it is only a test, not a solution).

## What the verifier checks

1. Tree provenance: working tree still at the pinned commit, no fetched
   objects, only the minimal file surface modified (the derive code
   generator source and/or the project's own test file), no new files —
   checked by hashing the working-tree bytes, not by git status.
2. Harness integrity: the golden test, the cargo/rustc binaries and the
   crates.io registry sources still match hashes recorded when the image
   was built.
3. The in-repo serde crates are rebuilt from source inside the verifier,
   then the project's regression test for this bug passes via `cargo test`.
4. The full `test_macros` integration suite still passes with your fix.
5. Several authored hidden cases pass — variations of this exact code path
   that the upstream regression test does not cover: other tagged-enum
   flavors (internal tag only; multiple variant payload shapes), different
   tag names, extra non-flatten fields, and more than one flattened field.

Deliverable: the repaired `/app/src` tree.