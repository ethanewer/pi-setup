# Respawn of a pane crashes the whole server when a control-mode client is behind

## Symptom (as a user would report it)

While a control-mode client (`tmux -C attach`) is attached to a session, run
`respawn-pane -k` on a pane in that session. If the control client has fallen
behind on that pane's output, the **entire tmux server dies within a couple of
seconds**: the client's next command starts failing with "no server running",
the session is lost, and every other attached client is kicked out too. A
client ends up behind when its output is not being drained — for example it is
piped into a fifo that nobody reads — or when the pane's window is moved into
another session so the client's read position stops advancing.

The server must, instead, keep running and keep serving the session after a
pane respawn, no matter how far behind any attached control client is.

## Environment

- `/app/src` is a `git` clone of the tmux project, detached at a pinned commit
  (the bug is present in this tree). The project is already configured and
  **already compiled**: `/app/src/tmux` is a working build. After you change C
  sources, rebuild with `make` in `/app/src` (a full rebuild takes under a
  minute on this machine). Do not run `make clean`, `make distclean` or a
  re-configure: the checker rebuilds in place and expects the existing build
  state.
- tmux needs no daemon and no display; it runs against a socket under `/tmp`
  with detached sessions (`tmux -L<label> -f/dev/null new -d ...`). Control
  clients attach with `tmux -L<label> -f/dev/null -C attach -t <session>` and
  keep stdin open (e.g. `( sleep 60 ) | tmux ... -C attach`).
- The container has no network. Everything you need is on disk. `/opt/` and
  `/solution/` belong to the harness: do not read or modify them.
- Do not modify anything outside `/app`. The fix must be a small source change
  inside the clone at `/app/src` — don't rebuild the project with different
  options, don't replace the binary with a downloaded one, don't patch shared
  libraries. The checker assumes a minimal source diff and rejects unrelated
  modifications to the tree.

## What to do

### 1. Write a reproduction script (deliverable)

Create `/app/repro.sh`, a standalone POSIX `sh` script that demonstrates the
bug and verifies the corrected behaviour using the tmux binary itself:

- it must honour a `TEST_TMUX` environment variable naming the tmux binary to
  test, defaulting to `/app/src/tmux` when unset, and use `$TEST_TMUX` for
  every invocation (client and server are the same binary);
- it must create a detached session with a pane that produces continuous
  output, attach at least one control-mode client whose output is **not being
  drained** (a fifo nobody reads is a fine way), let it fall behind, then
  respawn that pane; the moved-window configuration described in the symptom
  is the reliable way to expose the failure — a reproduction that does not
  actually crash the buggy build will be rejected;
- afterwards it must require the **server process to still be alive** (and
  still answer ordinary client commands) a few seconds after the respawn;
- it must print a short diagnostic to stderr and **exit non-zero if and only
  if the server died or stopped responding**; exit `0` when the server
  survived and responded.

The checker runs your script with `TEST_TMUX` pointing at a pristine copy of
the *unfixed* build (your script must fail there, proving it really reproduces
the bug - the checker also repeats this against a byte-identical copy of the
unfixed build placed at a different path, so decide from the behaviour, not
from where the binary happens to live), and with `TEST_TMUX` pointing at your
repaired build (your script must pass). Write it so all of those hold.

### 2. Fix the bug

Fix the underlying bug inside `/app/src` so your reproduction passes and a
respawned pane behaves identically whether or not a control client is behind.
You will need to work out where in the project the pane respawn path is and
what state it keeps per control client. Keep the change as small as the bug
allows.

### 3. Rebuild and validate

Rebuild with `make` in `/app/src`, then confirm your reproduction passes
against the rebuilt binary. Also run this slice of the project's own test
suite and confirm it stays green (the project's regress scripts take
`TEST_TMUX`):

```
cd /app/src
for t in pane-ops window-ops control-client-sanity capture-pane-sgr0 pipe-pane; do
  TEST_TMUX=/app/src/tmux sh regress/$t.sh || echo "$t FAILED"
done
```

An independent checker will additionally run the project's own regression
test for this bug and further respawn/control-client scenarios against your
repaired tree, so fix the behaviour, not the symptoms, and do not disable or
weaken the control-mode output path.

## Deliverables

- `/app/repro.sh` — the reproduction script described above (executable).
- `/app/src` — the repaired repository, still a git checkout with the bug
  fixed as a minimal source change, rebuilt so `/app/src/tmux` reflects the
  fixed sources.