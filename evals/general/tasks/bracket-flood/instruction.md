# Fix RESTORE silently dropping keys on an oversized relative TTL

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

A ready-made reproducer is installed at `/app/reproduce.sh` (it drives the
Tcl script `/app/reproduce.tcl` against a throwaway server it starts itself).

## The problem

Redis's `RESTORE` command can recreate a key from its serialized
`DUMP`-produced payload and, optionally, attach a time-to-live. When a very
large **relative** time-to-live is supplied — a value close to, or equal to,
the largest 64-bit signed integer — the command misbehaves silently:

- the command replies `OK` (it does not refuse the value), but the freshly
  recreated key is **immediately gone**: the next `EXISTS` returns `0`, as if
  the key had expired the instant it was created, although nothing aged;
- if the command is allowed to replace an existing key (`REPLACE`), the old
  value is **deleted** too, and the server's `expired_keys` counter
  (`INFO stats`) increments even though no key actually reached its
  expiration time.

So any script that restores keys from a dump with a large safety-margin TTL
gets an `OK` back and loses all of its data, with no error at all. The
correct behaviour is to refuse the out-of-range TTL, exactly as the command
already refuses other impossible time values.

Run the reproducer now to see the defect:

```sh
bash /app/reproduce.sh
```

At the current tree state you should observe `restore result: caught=0
reply="OK"`, the key vanishing right after the restore, and
`expired_keys` increasing. (If it shows an `invalid expire time` error, stop
— the tree is not the snapshot you were told it is.)

## Expected behaviour

A relative TTL whose value, added to the current server time, overflows the
64-bit timestamp must be refused before anything is written:

- the command replies with an error, exactly
  `ERR invalid expire time in 'restore' command`,
- an existing key being replaced is left untouched: same value, same TTL,
  as if the command had never run,
- a fresh key is not created at all,
- the server's `expired_keys` counter does not change.

Ordinary TTLs must keep working exactly as before: a normal positive
relative TTL still sets an expiry on the restored key, and a large value is
still valid when the caller explicitly marks it as an **absolute** timestamp
with the `ABSTTL` option (absolute timestamps are not offset by the current
time and must not be rejected).

## Your job

1. **Reproduce** the defect with the provided reproducer (or your own
   equivalent against a server you start).
2. **Localise and fix the real bug in the source tree.** The bug is a
   single missing guard around an arithmetic operation in one command
   handler: the handler converts the relative TTL to an absolute expiry by
   adding the current time without checking that the addition overflows.
   The fixed tree must keep building with the project's own build system.
3. **Rebuild** the server so the running binary contains your fix:
   `make -C /app/src -j1` (incremental; only changed files recompile).
4. **Verify** with the reproducer that the symptom is gone and with the
   project's own test suite that nothing broke (see below).
5. **Write up** the root cause in `/app/diagnosis.md`.

## Verifying your fix

Re-run the reproducer:

```sh
bash /app/reproduce.sh
```

It must now print `caught=1` with `reply="ERR invalid expire time in
'restore' command"`, and both the key-survival lines and the
`expired_keys` counter must be unchanged by the attempts.

Then run the project's own existing unit suite for the affected area (do
not modify any test while doing so):

```sh
cd /app/src && ./runtest --single unit/dump
```

All of its tests (DUMP / RESTORE round-trips, TTL handling, MIGRATE) must
pass. The normal-path RESTORE behaviour you rely on — same value, expiry, and
`expired_keys` semantics — is exercised there.

## Deliverables

- the **fixed source tree** under `/app/src` (the defect corrected at its
  root — a guard that rejects the overflowing value before any write — and
  nothing else changed), with the **rebuilt server binary**
  `/app/src/src/redis-server` reflecting your fix,
- a root-cause write-up at **`/app/diagnosis.md`**: what triggers the
  misbehaviour, the precise mechanism (which arithmetic overflows and what
  the corrupted value causes the command to do), and what change fixes it.
  Mention the `RESTORE` command by name.

## Constraints

- Fix the root cause in the source tree. Workarounds outside the source are
  not acceptable: no wrapper scripts around the binary, no configuration
  knob toggles, no disabling of tests.
- A fix may not paper over the symptom: do not weaken the build, delete code
  paths, or reject valid requests (in particular, do not reject large
  absolute timestamps).
- Do not modify, delete, rename or disable any test file, any test data, or
  the test harness.
- Leave the rest of the tree exactly as upstream has it: the verifier
  rejects unrelated changes.

The write-up will be read by a human reviewer; the tree and binary are
graded by an automated verifier (behavioural checks plus the project's own
test runner).