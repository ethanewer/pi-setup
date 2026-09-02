# systemd Service Unit Fix

You are administering a server that manages a **Watcher** background process through systemd. Under systemd, a long-running executable is described by a *service unit* file: a `.service` file whose `[Unit]` section describes the unit, whose `[Service]` section declares the command that launches the managed process (via `ExecStart`), and whose `[Install]` section declares when it is started.

There is a unit file at `/app/watcher.service` and the real executable/script that must run in the background is at `/app/watcher.sh`.

## Task

Edit `/app/watcher.service` so that the systemd unit launches the correct process, and save the result back to `/app/watcher.service`. Specifically:

1. The `[Service]` section's `ExecStart` must point to the real process launcher, `/app/watcher.sh` (and must **not** reference the stale `/app/missing_watcher.sh`).
2. Keep the `[Unit]` and `[Install]` sections intact and valid.

The file must remain a syntactically plausible systemd unit file (all three sections present). No other files need to be created.

## Verification

The checker reads `/app/watcher.service` and confirms that:
- It contains `[Unit]`, `[Service]`, and `[Install]` sections.
- The `ExecStart` value points to `/app/watcher.sh`.
- It does not reference `/app/missing_watcher.sh`.

Produce the file at exactly `/app/watcher.service`.