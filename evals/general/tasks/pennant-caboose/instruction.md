# Redis reports negative consumer-group lag, and its snapshots stop loading, after lowering a stream's entries counter

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

Files under `/opt`, `/tests` and `/solution` are harness-owned: do not read
or modify them. (`/solution` holds the reference answer and is present only
so the harness can mount it; you are not to look at it.)

## The problem

Redis streams can record a total-number-of-entries counter alongside the
stream itself, and that counter can be adjusted afterwards with the
`XSETID` command and its `ENTRIESADDED` option. Consumer groups track how
many entries of the stream they have read (`entries-read`), and `XINFO
GROUPS` reports each group's read position together with a **lag** — the
number of stream entries the group has not yet read.

Since this option can be provided by users and by tooling that restores or
repairs stream data, it is legal to set the counter to a value **lower**
than what the stream previously held. For example, after entries have been
trimmed away, `XSETID key <id> ENTRIESADDED <n>` is routinely used to bring
the counter in line with the trimmed stream.

When that happens, a consumer group that had already read the removed
entries keeps reporting a read position **higher than the stream's own
counter**:

- `XINFO GROUPS` reports an `entries-read` value above the stream's
  `entries_added`, and the reported **lag goes negative** — a consumer
  group is said to be "ahead" of a stream that is itself shorter than the
  group's position;
- far worse, a snapshot taken at that moment can **no longer be loaded back
  into the server**: `DEBUG RELOAD` fails, and the same failure strikes a
  server restart, a failover, or a replica full-sync that replays the
  snapshot. In practice the database is left wiped on the reload attempt.

Redis should never report a negative lag, and it should never persist a
stream/group state that its own loader refuses to load. Lowering the
stream's counter must also pull the groups' read positions back so the
invariant "a group has not read more entries than the stream contains" holds
everywhere, and so a snapshot taken after the `XSETID ... ENTRIESADDED`
command loads back cleanly.

## Your job

Work in stages, and do them in this order:

1. **Write your own failing reproduction.** Create `/app/reproduce.sh`
   (described below) that drives a real Redis server through the scenario
   and demonstrates the defect — before you change a single line of the C
   source. At this stage the script must end with `VERDICT: BUGGY`.

2. **Localise and fix the real bug in the source tree.** Find the root
   cause of the inconsistent group read positions and repair it there, at
   the point where a stream's `entries_added` counter is lowered. Do
   **not** paper over the symptom anywhere else: no changes to `XINFO
   GROUPS` output, no changes to the lag calculation, no changes to the RDB
   dump or loader to bypass the check, no configuration toggles, no wrapper
   scripts.

3. **Rebuild** so the running binary contains your fix:
   `make -C /app/src -j1` (incremental; only changed files recompile).

4. **Verify.** Re-run `/app/reproduce.sh` against the rebuilt binary: it
   must now end with `VERDICT: FIXED`. Then prove you broke nothing with
   the project's own test suite (see below) before finishing.

## The reproduction script contract

`/app/reproduce.sh` is a deliverable, and the verifier will run it twice —
once against the rebuilt binary, and once against a pristine pre-fix build
to confirm it honestly detects the defect. It must therefore be driven
rather than hard-coded. Conform to this contract exactly:

- Optional first argument: path to a server binary. If given, use it.
  Otherwise respect the environment variable `REDIS_SERVER_BIN`; if that is
  unset, default to `/app/src/src/redis-server`.
- Respect the environment variable `REDIS_PORT` (a TCP port for the server
  to listen on); if unset, default to `6391`. Do not pick a port yourself
  when `REDIS_PORT` is set, and do not collide with other instances — the
  verifier runs several servers in sequence.
- Start the server itself, wait until it accepts commands (poll `PING`, do
  not sleep a fixed amount), run the scenario, and shut the server down
  again before exiting.
- Drive the scenario against the server you started and **derive the
  verdict from what the server actually reports** (the group read
  positions, the lag, and whether a snapshot taken at that point loads
  back). Print the observed facts to stdout as you go.
- End with exactly one final line, `VERDICT: BUGGY` or `VERDICT: FIXED`,
  and exit 0 whenever the script ran to completion (the verdict line alone
  carries the outcome — the verifier parses it, including when the script
  is pointed at a broken server).

The verifier must be able to tell, by running the script against the
pre-fix binary, that your script genuinely detects the defect — a script
that reports `FIXED` no matter which binary it is given is not a
reproduction and fails the task.

## Verifying your fix with the project's own tests

The project's standard test runner is `./runtest` at the repository root.
The stream consumer-group unit tests live under `tests/unit/type/`. Run the
existing ones that cover consumer groups, read positions and trimming, for
example:

```sh
cd /app/src && ./runtest --single unit/type/stream-cgroups --only "XGROUP CREATE with ENTRIESREAD larger than stream entries should cap the value"
cd /app/src && ./runtest --single unit/type/stream-cgroups --only "XGROUP SETID with ENTRIESREAD larger than stream entries should cap the value"
```

Those two pre-existing tests pin the established rule that a group's read
position is capped so it never exceeds the stream's entry counter; your fix
must keep that rule intact (and correctly extended to the `XSETID ...`
path). You may run the whole consumer-group suite
(`./runtest --single unit/type/stream-cgroups`) if you like — it takes a
couple of minutes. Do not modify, rename or disable any existing test file.

## Deliverables

- `/app/reproduce.sh` — your reproduction script, conforming to the
  contract above.
- the **fixed source tree** under `/app/src` (the defect corrected at its
  root and nothing else changed), with the **rebuilt binary**
  `/app/src/src/redis-server` reflecting your fix.

## Constraints

- Leave the rest of the tree exactly as upstream has it: the verifier
  rejects unrelated changes to tracked files and rejects new files added
  inside the clone. The fix belongs in the source of the command that
  carries the affected behaviour; nothing outside that source file may
  change.
- Do not modify, delete, rename or disable any test file, any test data, or
  the test harness.
- Do not touch anything under `/opt`, `/tests` or `/solution`.

## What the verifier checks

1. Your reproduction script exists and is executable, and it honestly
   detects the defect: run against the pristine pre-fix binary it must
   print `VERDICT: BUGGY`, run against your rebuilt binary it must print
   `VERDICT: FIXED`.
2. Provenance: the clone is still at the pinned snapshot, the only tracked
   change is the file the fix actually requires, no stray files were added,
   and the tree still builds.
3. The project's own regression test for this exact behaviour — extracted
   at image build time from the fixing revision of the project's
   `stream-cgroups.tcl`, so it is never present in your tree — passes via
   `./runtest` against your rebuilt binary. It asserts the group read
   position is clamped to the lowered counter, that `XINFO GROUPS` reports
   no negative lag, and that a `DEBUG RELOAD` of the resulting snapshot
   succeeds.
4. Authored hidden cases that drive the same code path from inputs the
   upstream regression test does not use.
5. The project's own existing stream consumer-group tests stay green,
   including the two "cap the value" tests named above.