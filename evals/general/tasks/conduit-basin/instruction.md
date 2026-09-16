# Redis --bigkeys must report a zero-size key as the biggest of its type

## Environment

`/app/src` is a real upstream checkout of **Redis** (the in-memory data
store), pinned to a single snapshot: the working tree is `HEAD` of the clone
and it is the latest snapshot at which the defect described below still
exists. The checkout is **shallow and detached** — there is exactly one
commit in the clone, so there is no history to consult and nothing to fetch.
The tree is fully writable and buildable offline.

The project is already built in the image:

- `/app/src/src/redis-server` and `/app/src/src/redis-cli` — the build
  output (the default developer build, jemalloc allocator),
- `/app/src` — the full C source tree plus the project's own Tcl test
  framework (the `./runtest` runner at the repository root),
- toolchain: gcc, make, `tclsh` (Tcl 8.6), plus the usual shell tools.

There is **no network** in this container. Everything you need is already on
disk; do not attempt to download anything. In particular, do not try to
`git fetch` from the upstream remote: it cannot work here.

A ready-made reproducer is installed at `/app/reproduce.sh`. It starts a
throwaway Redis server, stores a single empty string key, and drives the
two keyspace-summary modes of `redis-cli` (`--bigkeys` and `--keystats`)
against that server, printing what they report.

## The problem

`redis-cli` has a keyspace summary mode that scans an entire database and
reports, per key type (string, list, set, hash, zset, stream), on one hand
how many keys of that type it found and their total size, and on the other
hand which single key is the **biggest** of that type. The biggest key is
printed as a line of the form

```
Biggest string found "foo" has 5 bytes
Biggest list found "mylist" has 60000 items
```

When the biggest key of a type has size **zero** — for example an empty
string, created with `SET foo ""` — the scanner still counts that key in
the per-type totals line (`1 strings with 0 bytes (100.00% of keys, avg
size 0.00)`), but it **never reports it in the biggest-key summary**: no
`Biggest string found "foo" has 0 bytes` line appears for that type at all.
The report silently omits the largest such key, as if the type had none.

The same gap shows up in `redis-cli --keystats`: its "Top length and
cardinality per type" section omits a zero-length string even though the
string type is non-empty.

Expected behaviour: a zero-size key is reported as the biggest of its type
exactly like any other key. When the largest string in the database is
empty, the line `Biggest string found "foo" has 0 bytes` must appear —
counted in the totals *and* named in the biggest-key summary.

## Reproducing the failure

```sh
bash /app/reproduce.sh
```

At the current tree state you should see `STATE=BUGGY` at the end: the
`--bigkeys` output contains the `1 strings with 0 bytes ...` totals line and
the `Sampled 1 keys` line, but **no** `Biggest string found ...` line for
the string type, and the `--keystats` output's length section is missing the
string entry. (If it reports `STATE=FIXED` and the lines *are* present, stop
— the tree is not the snapshot you were told it is.)

## Expected behaviour

After your fix, the same run must print `STATE=FIXED`, and both outputs
must name the empty string key in the biggest-key lines:

- `--bigkeys` prints `Biggest string found "empty" has 0 bytes`,
- `--keystats` prints `string "empty" has 0B` in its "Top length and
  cardinality per type" section.

Ordinary keys must keep working exactly as before: a non-empty largest key
is still reported (e.g. a 5-byte string yields
`Biggest string found "big" has 5 bytes`), sizes and totals are unchanged,
and no other type's biggest-key line is affected.

## Your job

1. **Reproduce** the defect with `/app/reproduce.sh` (or your own
   equivalent against a server you start).
2. **Localise and fix the real bug in the source tree.** The defect is in
   the per-type bookkeeping of the keyspace scanner: the code that
   remembers the biggest key seen for a type only fires when a sampled key
   is *strictly* larger than the biggest seen so far, and every type starts
   at zero, so a key whose size is exactly zero is never remembered — even
   when it is the largest such key — and is therefore absent from the
   summary. Fix it at the root. Do not change what is counted, do not
   change reported sizes or totals, and do not change the behaviour for
   non-empty keys.
3. **Rebuild** so the running binary contains your fix:
   `make -C /app/src -j1` (incremental; only changed files recompile).
4. **Verify** with the reproducer that the symptom is gone, and with the
   project's own test runner that nothing broke (see below).

## Verifying your fix

Re-run the reproducer:

```sh
bash /app/reproduce.sh
```

It must now print `STATE=FIXED` and show the empty key in the biggest-key
lines of both modes.

Then exercise the project's own existing redis-cli integration tests.
For example, from `/app/src`:

```sh
cd /app/src && ./runtest --single integration/redis-cli --only "keystats on empty database should not produce garbage stats"
```

That is a pre-existing test for the adjacent `--keystats` code path and must
pass unchanged. You may write your own scratch tests (for example exercising
`--bigkeys` against a server with several empty strings, mixed-encoding key
names, or an empty string next to larger keys) to convince yourself, but do
not modify, rename or disable any existing test file while doing so.

## Deliverables

- the **fixed source tree** under `/app/src` (the defect corrected at its
  root and nothing else changed), with the **rebuilt binary**
  `/app/src/src/redis-cli` reflecting your fix.

Workarounds outside the source are not acceptable: no wrapper scripts around
the binary, no configuration toggles, no compensation in the test output.

## Constraints

- Leave the rest of the tree exactly as upstream has it: the verifier
  rejects unrelated changes to tracked files and rejects new files added
  inside the clone.
- Do not modify, delete, rename or disable any test file, any test data, or
  the test harness.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them.

## What the verifier checks

1. Provenance: the clone is still at the pinned snapshot, the working tree
   carries only the minimal change the fix requires (no other tracked file
   modified, no new files added), and the tree still builds.
2. The project's own regression test for this behaviour — extracted at
   image build time from the fixing revision of the project's redis-cli
   integration test file, so it is never present in your tree — must pass
   via `./runtest` against the built binary.
3. Authored hidden cases that drive the same code path from inputs the
   upstream regression test does not use: an empty string among keys of the
   other four types, several all-empty strings, and the `--keystats` length
   report for a zero-length string.
4. The project's own pre-existing redis-cli integration tests stay green
   (including the `--keystats` empty-database test and the `--bigkeys`
   big-key reporting paths).