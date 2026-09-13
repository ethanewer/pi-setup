# Synchronization breaks when a peer sends a directory entry with the synthetic directory size

## Situation

`/app/src` is a shallow, pinned clone of the syncthing repository
(`https://github.com/syncthing/syncthing`) at upstream commit
`ee275fee65b37ea75802c8fc3c9decd5a66cb065`, checked out in detached HEAD.

A Go 1.27.1 toolchain is installed at `/usr/local/go`, the project's
go.sum-pinned dependency sources are already downloaded, and the protocol
package test module is pre-built — so everything works entirely offline.
There is **no network** at trial time: `go test`, `git fetch`, `curl` and
any other network use will fail. Only the test module under `./lib/protocol/`
is guaranteed to have all its dependencies cached, so keep your test runs
inside that module.

The project's test runner is the standard `go test` command:

```
cd /app/src && go test ./lib/protocol/ -v
```

## The bug

When two syncthing nodes of different versions synchronize a folder, the
receiving node checks every incoming index entry for internal consistency
before accepting it. One check says that a non-file entry (a directory or a
symlink) must not carry a nonzero size — the entry is rejected as invalid
protocol data and synchronization of the affected items fails.

Newer syncthing versions stamp a **fixed small nonzero synthetic size** on
directories while scanning (it is the same value for every directory, and it
is deliberately not the real directory size, which is 0 bytes on disk).
A node running this check therefore flags every incoming directory entry
from such a peer as inconsistent, reports an error of the form

```
non-file type with nonzero size
```

treats the directory entries as invalid protocol data, and mixed-version
synchronization of directory entries is disrupted. Size-zero directories and
symlinks are fine and must remain fine; so must every other rejection the
check performs.

The shipped regression case `TestCheckConsistency` in the package's test
module is authoritative: it must pass once the bug is fixed, and it currently
fails. You can see the failure with:

```
cd /app/src && go test ./lib/protocol/ -run TestCheckConsistency -v
```

which reports one table row rejected with `Unexpected error non-file type
with nonzero size (want nil) for Directory{...}` even though the entry is a
valid directory as newer versions stamp it.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. an index entry for a **directory whose size equals the fixed synthetic
   directory size** is accepted — this is the value other syncthing versions
   stamp on every scanned directory, and the reason mixed-version
   synchronization of directory entries breaks;
2. a directory with size zero remains accepted, and a directory with any
   other nonzero size (for example a value that looks like a real file size,
   or an arbitrary small value) is rejected exactly as before;
3. symlink entries remain valid only at size zero: a symlink with any nonzero
   size, including the synthetic directory size itself, is still rejected.

Drive your work with the project's own test module:

```
cd /app/src && go test ./lib/protocol/ -v
```

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or
  change build files, and do not add or rename files inside the repository.
- The regression test under `lib/protocol/protocol_test.go` is part of the
  image exactly as the upstream project shipped it; the verifier checks that
  it stays byte-identical.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the only differences from it are
   the minimal source change that fixes the bug plus the regression test
   the image already carries, and nothing new inside the repository.
2. The project's own regression case `TestCheckConsistency` passes against
   the repaired tree.
3. The whole protocol package test module passes end to end
   (`go test ./lib/protocol/ -v`), including the pre-existing filename,
   block-size, marshalling, encryption and connection cases.
4. Hidden cases: the consistency check is exercised on additional directory
   and symlink index entries the shipped tests do not cover (nested directory
   names, deleted directories, a directory just below the synthetic size,
   a directory whose size looks like a real file size, symlinks with
   multi-component targets, and symlinks with a one-byte or near-synthetic
   size) and each must be accepted or rejected with exactly the semantics
   described above.

Deliverable: the repaired `/app/src` tree.