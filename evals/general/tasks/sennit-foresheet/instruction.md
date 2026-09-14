# sennit-foresheet — fix a real tmux bug

You are dropped into a real upstream checkout of **tmux**, the terminal
multiplexer, with a real, user-reported bug still in it. Your job: build a
reproduction, find the cause, fix it, and prove the fix with the project's
own machinery.

## Environment

- `/app/src` is a git checkout of the `tmux/tmux` upstream repository,
  detached at a specific upstream commit, with the bug PRESENT. Work in this
  tree. Do not re-clone, fetch history, touch git internals, or modify files
  outside `/app/src` and the deliverable paths below.
- tmux is already compiled: `/app/src/tmux` runs (`/app/src/tmux -V` prints
  a version). The toolchain is installed (gcc, make, autoconf, automake,
  libtool, bison, libevent/ncurses/libutempter headers). After editing
  sources, rebuild with `make -j1` inside `/app/src`; an incremental rebuild
  relinks in seconds at 1 CPU.
- The upstream tree ships a self-contained shell test-suite under
  `/app/src/regress/`. Its scripts start throwaway tmux servers on sockets
  in `/tmp` and need no network, no display and no terminal. To run one of
  them:
  `(cd regress && TEST_TMUX=$PWD/../tmux sh ./<script>.sh)`
- Do not rely on network access; treat the task as offline. The checkout
  contains exactly one commit, so no answer (and no future history) is
  readable from the repository itself. Solve it from the code in front of
  you.

## The bug (user report)

Some tmux commands that take a *session-relative* target of the form
`session:window` or `session:window.pane` silently accept a **malformed
numeric offset** in the window or pane part — for example `+0`, `+foo` or
`-0` where `+N`/`-N` means "N windows/panes forward/back". No error is
printed. The command quietly acts on the fallback item instead (the first
window for a `+` offset, the wrapped-around previous for a `-` offset), so
the request *appears* to succeed while applying to the wrong window or pane.
A mistyped number gets you no error at all.

Reproduce carefully: the symptom shows up with commands that resolve the
target *strictly*. `select-window`, `select-pane` and `has-session -t`
(among others) resolve `session:window[.pane]` strictly and print an error
when the target cannot be resolved; some other commands (like
`display-message`) are intentionally lenient when a target does not resolve,
so do not use those to reproduce. Session-relative here means the target
names an existing session, e.g. `-t alpha:+0` or `-t alpha:1.+0`.

## What to produce

### 1. `/app/repro.sh` — your own reproduction (write it first)

An executable POSIX shell script that takes the tmux binary to test from the
`TMUX` environment variable (default `/app/src/tmux`), starts a throwaway
server on a `/tmp` socket, drives a strictly-resolving, target-aware command
with one or more malformed session-relative `+N`/`-N` window or pane
targets, and:

- exits `0` when the binary behaves correctly: the malformed target is
  rejected with an error (command exits non-zero; `has-session -t` or an
  equivalent prints the "can't find ..." message); and
- exits non-zero, printing a one-line diagnostic to stderr, when the bug is
  present: the malformed target is silently accepted.

So `/app/repro.sh` must FAIL against the current buggy build and PASS once
you fix the bug. Prove both directions yourself before moving on. Clean up
your throwaway server on exit.

### 2. `/app/src` — the fixed tree

Fix the bug in the real source. The project must rebuild cleanly with
`make -j1` and print no new warnings that matter. Do not:

- modify the build system or `Makefile.am` chain,
- delete tracked files or add git commits/history,
- disable, skip or neuter any of the project's tests, or special-case any
  test inputs.

Note: upstream development happens in the open — but the fix for this bug
is not in the checked-out history (the checkout contains exactly one
commit), and looking the answer up is not the point of this task. Reproduce
it, then fix it.

## Acceptance checks (run these before you finish)

1. `make -j1` in `/app/src` succeeds and `/app/src/tmux -V` works.
2. `/app/repro.sh` fails against the unfixed build and passes against your
   fixed build (rebuild, then run it with `TMUX=/app/src/tmux`).
3. The project's own target-resolution regression scripts under `regress/`
   pass with your build (`sh ./targets.sh`, `sh ./targets-panes.sh`), and a
   representative slice of the rest of the suite still passes too.
4. `git -C /app/src status --porcelain` shows only your changes to the
   relevant source file(s) and any new untracked files you added; no
   tracked test files modified.

## Honesty

The verifier checks the semantics, not the file layout. Hardcoding an
expected result, wrapping the command, or removing a test will be detected:
reproduce the bug for real, fix it for real.