# Corrupted HTTP cache entries crash uv instead of being rejected

## Situation

`/app/src` is a shallow, pinned clone of the `uv` repository
(`https://github.com/astral-sh/uv`) at a specific upstream revision, checked
out in detached HEAD. That revision has the bug described below.

Everything builds and runs entirely offline. The Rust toolchain pinned by the
repository's own `rust-toolchain.toml` (channel 1.96.0) is installed, the
`Cargo.lock` is committed in-tree, the crate dependency cache is warm, and the
`uv-client` test harness described below is **already compiled** — after you
edit a source file, the next `cargo test` recompiles only what changed
incrementally (~10 seconds on this single-CPU container). There is **no
network** at trial time: cargo is configured offline, and `git fetch`,
`curl` and any other network use will fail.

## The bug

`uv` keeps an on-disk HTTP cache so that repeated reads of package index
metadata, wheels and other HTTP payloads do not re-fetch them. Each cached
entry on disk is stored as a blob of fetched data followed by a cache policy
(a record describing the response, its freshness and the request it was for),
and the whole entry carries a small **length marker in its trailing bytes**
that records how long the policy section is.

If a cache entry on disk becomes corrupt so that this trailing length marker
encodes an enormous value (for example, a mangled or truncated cache file
whose last bytes are all `0xFF`), the reader that loads cached responses
crashes with a Rust arithmetic-overflow panic instead of treating the entry
as corrupt and simply discarding it. The panic ends in
`attempt to add with overflow`. Any operation that reads cached HTTP
responses back from disk — refreshing package index metadata after a network
blip, resolving dependencies, installing tools — can crash on one mangled
cache file instead of recovering gracefully.

The harness that decides whether the bug is present is the project's own
`uv-client` integration test target. Run the failing test:

```
cd /app/src
cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact
```

This test feeds the cache-entry reader exactly such a corrupt entry (its
trailing length marker decodes to the largest possible value) and expects the
reader to reject it as a malformed-archive error — as it stands, the test
**panics** instead:

```
thread 'cached_client::reject_overflowing_cache_policy_length' panicked:
attempt to add with overflow
test result: FAILED. 0 passed; 1 failed; ...
```

That panic is the bug. The reader must be fixed so malformed entries are
rejected as ordinary errors.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. The regression test passes:

   ```
   cd /app/src
   cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact
   ```
   reports `ok` (1 passed; 0 failed).

2. Cache entries whose trailing length marker is huge, overflows the
   reader's arithmetic, or claims a policy longer than the buffer are
   rejected as `ArchiveRead` errors — never a panic, never a crash.

3. Perfectly valid cache entries still load: the reader must keep accepting
   well-formed entries and return their data intact.

4. The offline part of the project's own integration suite still passes:

   ```
   cd /app/src
   cargo test -p uv-client --test it -- cached_client proxy ssl_certs user_agent_version
   ```
   reports 26 passed (the `remote_metadata` test in that target needs network
   access and is not part of the grade; it cannot run offline).

The tests in the tree are the spec: drive your work with them. The full
compiled harness runs in a small fraction of a second once built.

## Constraints

- Network is unavailable; everything needed is installed and compiled.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or add
  or rename files inside the repository, and do not modify the regression
  test files under `crates/uv-client/tests/it/` (they are part of the image
  the way the upstream fix intended; the verifier checks them byte-for-byte).
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned revision; the only differences from the
   upstream checkout are the minimal source change that fixes the bug plus
   the regression test the image already carries, and nothing new inside the
   repository.
2. The regression test above passes against the repaired tree, and the
   offline `uv-client` integration suite (26 tests) passes end to end.
3. Hidden cases: additional corrupt entries with different overflowing
   length markers (with and without data payloads) must be rejected as
   `ArchiveRead` errors rather than panicking, and a real cache entry
   produced by uv's own cache writer must still load with its data intact.

Deliverable: the repaired `/app/src` tree.