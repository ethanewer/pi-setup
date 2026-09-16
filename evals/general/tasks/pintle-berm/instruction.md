# Leftmost match starts too late when the pattern's first alternative is optional

## Situation

`/app/src` is a shallow, pinned clone of the `rust-lang/regex` repository at
upstream commit `bbf0b38df618734b92d7b92acc8a8bf31b6d0046`, checked out in
detached HEAD. The Rust toolchain (cargo/rustc 1.98.1) is installed at
`/opt/cargo` and the whole workspace is already compiled, so everything works
fully offline; cargo is configured to fail fast rather than hang if a crate
were ever missing.

The project's own test harness runs like this:

```
cd /app/src
cargo test --test integration -- suite_string::default
```

The harness compiles the test corpus in `/app/src/testdata/` into the test
binary at build time, and cargo already tracks files in that directory: after
you edit any testdata file, the next `cargo test --test integration` command
recompiles only what changed (a few seconds) and picks up your edit. Editing
Rust sources recompiles the affected crates, also incrementally.

## The bug

The library's `Regex::find` / `find_iter` API promises the **leftmost**
match: of all matches of the pattern, the one that starts at the smallest
byte offset, with capture groups aligned to that leftmost match. In this
checkout, one class of patterns violates that promise.

When the first alternative of a pattern is **optional** and the pattern has
the shape `<optional part><digits><separator><digits>`, a search can report a
match that is a real match of the pattern but starts **too late**, with the
captures shifted or missing. For example, searching the 9-character haystack
`102:12:39` with the pattern

```
(?:(\d+)[:.])?(\d{1,2})[:.](\d{2})
```

reports a match at byte offsets `1..9` whose groups are `[1..3], [4..6],
[7..9]`. But the true leftmost match starts at `0`: the optional group
`(\d+)[:.]` consumes `102:`, and the whole match spans `0..9` with groups
`[0..3], [4..6], [7..9]`. A simpler pattern on the same haystack,

```
(?:([0-9][0-9][0-9]):)?([0-9][0-9]):([0-9][0-9])
```

reports `1..6` with the optional group empty (`None`). In both cases the
reported span is a genuine match of the pattern — it is just not the leftmost
one the API guarantees — so callers see truncated, shifted, or empty capture
data and a match that starts later than any other valid explanation of the
text.

## Your job

Do all three, in this order.

1. **Write the failing reproduction yourself.** Add one or more new cases to
   the project's own regression-test data file
   `/app/src/testdata/regression.toml`, in the `[[test]]` format the existing
   entries use, that record the **correct** expected behaviour: the leftmost
   match with its exact byte offsets and capture groups for a pattern of the
   class above. Then run the harness (a `suite_string::default` run) and
   watch it fail on your new case. That failure is your proof that the bug is
   present in this checkout; keep the case in the file.
2. **Fix the library** in the checkout at `/app/src` so the harness is green
   with your reproduction in place. The fix must generalise, not special-case
   one string: the same class of patterns must yield the true leftmost match
   and correct captures for any haystack.
3. **Write `/app/report.md`**: a short summary (2-5 sentences) naming the
   case you added to `testdata/regression.toml`, saying why the
   implementation you found was wrong, and describing how your change fixes
   it.

## Constraints

- The run is fully offline. Everything needed is baked into the image; do not
  attempt any network use.
- Only `testdata/regression.toml` and the source fix it requires may differ
  from the pinned commit. Do not add, remove, or rename any other file; do
  not commit, branch, add remotes, tag, or otherwise touch history.
- `/opt/golden-regression.toml`, `/opt/pristine`, `/tests` and `/solution`
  exist only for the grading harness — do not read or modify them.
- After your change the whole repository must still build and its own test
  suites must stay green (the verifier runs the project's full integration
  suite and the changed crate's deep engine-level suite).

## What the verifier checks

- `/app/src` is still the pinned commit, the only differences are your
  reproduction in `testdata/regression.toml` and the minimal source fix, and
  no file was added, removed, or renamed.
- It copies **your** `testdata/regression.toml` into a pristine copy of the
  same commit and requires the harness to fail there (your reproduction must
  genuinely capture the bug), then requires the harness to pass in your
  repaired tree.
- It runs the upstream project's own regression test for this bug (extracted
  at image build time) against your repaired tree — it must pass.
- It runs your reproduction, the project's own full integration suite, the
  deep engine-level suite of the changed crate, and authored hidden cases
  built from other optional-prefix patterns and haystacks — all must pass.
- `/app/report.md` names the case you added.

Deliverables: the repaired `/app/src` tree and `/app/report.md`.