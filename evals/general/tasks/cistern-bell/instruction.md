# tmux: malformed target offsets are silently accepted

You are working inside a checkout of the real tmux source tree at
`/app/tmux` — a git clone of `tmux/tmux`, checked out at one pinned upstream
commit. The tree contains the tmux version labelled `next-3.8`. Your job is to
find and fix a real bug in this tree, rebuild tmux, and prove the fix with the
project's own tests.

## The bug

Giving a tmux command a session-relative window or pane target that carries a
malformed numeric offset — for example `+foo` or `-0` — is silently accepted
instead of rejected. The command quietly acts on the first (for `+`) or the
wrapped previous (for `-`) matching window or pane, so a command like

```
tmux -LtestX -f/dev/null select-window -t alpha:+foo
```

appears to succeed while applying to the wrong window. A mistyped offset
therefore gives no error at all.

The correct behaviour: any target whose numeric offset is not a valid positive
integer must fail with a server-side error that names the offending token,
`can't find window: +foo` for a window offset and `can't find pane: +foo` for
a pane offset, and the command must exit with a non-zero status. Plain `+` and
`-` (one step from the current window/pane, wrapping) and valid `+N`/`-N`
offsets must keep working exactly as before.

## Environment

- `/app/tmux` — the real tmux source tree (git clone, one pinned upstream
  commit, no history). All build prerequisites are already installed:
  `build-essential autoconf automake libtool pkg-config bison byacc
  libevent-dev libncurses-dev libutempter-dev`.
- The tree was already configured and built once in the image, so a rebuild
  after a source change is incremental.
- There is **no network** in this environment. Everything you need is on
  disk; do not try to fetch anything.
- The tree must remain a git checkout of that exact upstream commit: make your
  change in the working tree, do not create commits, and do not modify
  anything your fix does not require. In particular, do not touch the project's
  test scripts under `regress/`.

## Build

tmux's own build, from the tree root:

```
cd /app/tmux
./autogen.sh
./configure
make
```

This produces the `tmux` binary at `/app/tmux/tmux`.

## Reproduce and investigate

Run commands against a scratch server so you never touch your real terminal:

```
cd /app/tmux
./tmux -LtestX -f/dev/null new -d -x80 -y24 -s alpha
./tmux -LtestX -f/dev/null select-window -t 'alpha:+foo'; echo rc=$?
./tmux -LtestX -f/dev/null has-session -t 'alpha:+foo'; echo rc=$?
./tmux -LtestX -f/dev/null has-session -t 'alpha:+0';  echo rc=$?
./tmux -LtestX -f/dev/null kill-server
```

The last `kill-server` is fine even when nothing is running.

Also try `-t 'p:0.+0'` style pane offsets inside a window that has several
panes (create the panes with `split-window` first). Invalid and valid offsets
are both accepted today; after your fix the invalid ones must produce the
errors quoted above while the valid ones still resolve.

## The project's own tests

The tree carries tmux's regression suite under `regress/`. The two scripts
that exercise exactly this machinery are `regress/targets.sh` (window and
session target resolution) and `regress/targets-panes.sh` (pane target
resolution). Run them against your rebuilt binary:

```
cd /app/tmux/regress
TEST_TMUX=/app/tmux/tmux sh targets.sh && echo TARGETS-OK
TEST_TMUX=/app/tmux/tmux sh targets-panes.sh && echo TARGETS-PANES-OK
```

Before the fix, both scripts fail on the malformed-offset checks with a line
like `target 'alpha:+0' resolved (expected failure).`; after the fix both
must exit 0 with no output. Other tests in `regress/` that passed before your
change must keep passing.

## Deliverables

- `/app/tmux` — the repaired source tree: the real bug fixed in the real code,
  with the smallest change that fixes it and nothing else modified.
- `/app/tmux/tmux` — the freshly rebuilt binary produced from the repaired
  tree (an incremental `make` from the source change is fine).

The verifier will rebuild nothing for you: it runs your binary. It will run
the two project test scripts named above plus a set of additional hidden
checks against your binary, and it will verify the tree is still the pinned
upstream commit with only the changes your fix required. If your fix is
correct, all of them pass; if the tree or the binary does not behave as
required, you get nothing.

Do not leave any scratch tmux servers running when you finish
(`./tmux -LtestX -f/dev/null kill-server` twice is harmless).