# scupper-gulf

You are working inside a real upstream open-source project: **syncthing**,
a self-hosted file synchronisation daemon, checked out at a pinned commit in
`/app/src` (the working tree starts clean). There is a bug in this tree that
breaks transfers of **empty files between nodes running different versions**.
Your job is to find it, fix it in the working tree, and prove the fix by
writing your own failing reproduction first and making it pass. You are
deliberately **not** told which file or function to change: localising the bug
is part of the task.

## Environment

- A Go toolchain (1.26.3) is installed on `PATH` (`go`, `git`). The
  repository's `go.mod` pins every module dependency. Both the module
  download cache and the compiled-build cache are warm, so any `go test`
  invocation you run completes offline and quickly.
- Outbound network is not available and must not be relied on.
- `cpus = 1`: one vCPU. Do not launch parallel builds; the Go build system
  uses the single core.
- The tree at `/app/src` is shallow (one commit, detached). Do not commit,
  fetch, or otherwise modify `.git`; the grader checks that the working tree
  still points at the original pinned commit.

## The bug (user-visible symptom)

Syncthing nodes exchange file data with the Block Exchange Protocol (BEP).
When a node decides a file block is needed, it sends a "request" message
naming the file, a byte offset, and the number of bytes it wants. Nodes
running newer versions of Syncthing send perfectly legitimate requests with a
**byte count of zero** for the blocks of an **empty file** (there is nothing
to fetch, but the request is still part of the protocol handshake).

The bug: the receiving node treats any request whose byte count is **zero** as
a *protocol violation*. Instead of replying, it logs an error and
**terminates the connection** to the peer. Both nodes then keep reconnecting
and dropping, so a transfer of an empty file between a newer node and this
tree's node **never completes** — the transfer log on the newer node cycles
through "connection closed" / "protocol error" messages. Requests with a
negative byte count are also sent by buggy peers and should remain protocol
violations; only the zero-count case is wrong.

## Requirements

1. **Write a failing reproduction first.** Add a regression test to the
   protocol test suite of this tree (any `*_test.go` file under
   `/app/src/lib/protocol/`). Your test must exercise the package's
   in-memory connection harness the suite already uses (as the existing tests
   in `lib/protocol/protocol_test.go` do) and must **fail on the unmodified
   tree** — e.g. by sending a single zero-count block request over a
   connection and asserting that a well-formed reply comes back — while it
   **passes after the tree is fixed**. If your reproduction does not fail
   before the fix, it proves nothing and the grader rejects it.
2. **Fix the tree** so that a zero-count block request is accepted and
   answered, while requests with a negative byte count still count as
   protocol violations and still close the connection with an error. After
   the fix, the request/reply exchange in your reproduction completes and the
   connection stays up for further traffic.
3. **Break nothing else.** The full existing `lib/protocol` test suite must
   still pass after your change (run `go test ./lib/protocol/ -v`).
4. The repository must otherwise stay exactly as checked out: no commits, no
   new files outside the protocol test package, no renames or reformatting of
   existing files, and no other sources modified. The grader compares every
   file's bytes against the pinned commit and rejects cosmetic or unrelated
   edits. (The Go tool, when run, touches the tracked file `go.sum`
   harmlessly; leave that alone.)

## Deliverable

1. `/app/src` — the repository with (a) your fix applied to the working tree
   and (b) your regression test from requirement 1 present in the protocol
   test package. There is no separate report file; the state of `/app/src`
   when you finish is the deliverable.

## Verification commands you can use

```sh
cd /app/src
go test ./lib/protocol/ -run <YourTestName> -v   # your own reproduction
go test ./lib/protocol/ -v                        # entire protocol suite
```

`-run` filters the run to test names matching a regex, so you can isolate
your reproduction from the rest of the suite while developing.