# slate-fjord — Password-SSH mirror sync automation

You are the on-call ops engineer for **Tarrow Field Station**. The station
mirrors its field-ledger repositories onto an on-prem Git server that speaks
SSH on loopback. The server accepts **password authentication only** (public
key authentication is disabled server-side), the host key is not in any
trust store, and the nightly sync has to run **unattended** — nothing may sit
at an interactive prompt. Your job is to build and prove out that automation.

Tooling already installed: `git`, `sshpass`, `openssh-client`,
`openssh-server` (already running), `python3`. Work only under `/app` (plus
`/tmp`). Do **not** modify the served repositories under `/srv/git`, the SSH
daemon configuration, or system users/passwords. Do **not** read `/tests`
(it is hidden and irrelevant to you).

## The Git server

SSH daemon on `127.0.0.1`, port **22**, user **`deploy`**, password
**`bedrock7`**. The server accepts **only** password authentication. Bare
repositories are served from `/srv/git`:

- `deploy@127.0.0.1:/srv/git/ledger.git` — scp-like URL form (default port).
- Some station services run a second endpoint on port **2222** with the same
  user and password. Those remotes are addressed with `ssh://` URLs that carry
  the explicit port, e.g. `ssh://deploy@127.0.0.1:2222/srv/git/quartz.git`.

A remote URL given to your script may therefore be either the scp-like form
(host:path, port 22) or an `ssh://` form with an optional `:port`. Your host
key handling must be **port-aware**: a pinned key for port 22 does not match
a connection to port 2222 unless your known-hosts entry is recorded under the
bracketed `[host]:port` name.

## Deliverables (both required)

1. `/app/sync.sh` — a **self-contained, reusable, executable** Bash script:

   ```
   bash /app/sync.sh <remote-url> <target-dir> <message>
   ```

   Contract:

   - **Self-contained**: it may not rely on anything you left behind outside
     the script — not `/root/.ssh`, not a pre-seeded known-hosts file, not a
     global git config. It is graded under a pristine `HOME`, so it must set
     up its own host-key pinning and password automation at run time.
   - **Host keys**: pin the server host key into a known-hosts file of your
     own (fetching it with `ssh-keyscan` is acceptable for this trusted
     loopback server) and connect with **strict host-key checking enabled**.
     The script must **not** disable or relax host-key checking in any way:
     no `StrictHostKeyChecking=no`, no `StrictHostKeyChecking=accept-new`,
     and no equivalent workaround. This is enforced.
   - **Password automation**: complete the SSH password prompt
     non-interactively (the server only offers password auth, so `sshpass` or
     equivalent is required). The script is run with stdin at EOF and must
     finish on its own.
   - If `<target-dir>` already exists, remove it first and clone fresh.
   - Clone `<remote-url>` into `<target-dir>`; the clone's `origin` must be
     the given remote URL exactly (the transfer must really happen over SSH).
     This must work even when the remote repository is **empty**.
   - Write `<message>` (followed by a newline) to `manifest.txt` at the root
     of the working tree, overwriting any previous content. Every other
     tracked file must be preserved byte-for-byte.
   - **Empty remotes**: cloning an empty repository leaves an unborn initial
     branch (the client's init default, `master` on this image). Commit on
     that branch and push it, creating the branch on the remote; the pushed
     history must contain exactly one commit.
   - Commit that change with `<message>` as the commit subject, then push the
     current branch back to the **same branch name** on the remote — whatever
     the clone checked out (`main`, `master`, ...). A re-run against an
     already-synced remote may find the manifest unchanged: still create the
     sync commit (an empty commit is fine) so the push always advances the
     remote. Re-runs must succeed.
   - Exit `0` on success, non-zero on any failure. A single run must complete
     well within 120 seconds.

2. `/app/clone` — the working checkout produced by running your script on the
   visible remote:

   ```
   bash /app/sync.sh deploy@127.0.0.1:/srv/git/ledger.git /app/clone 'bootstrap mirror'
   ```

   After that command, `/app/clone` must be a valid git repository on branch
   `main` with `manifest.txt` containing exactly `bootstrap mirror`.

## Edge cases the grader probes (hidden remotes, same server/password)

- **Empty repository** (no commits yet): clone, commit, and push must create
  the remote branch; the pushed history must contain exactly one commit.
- **Non-`main` default branch**: a remote whose checked-out branch is
  `master` — the sync must push back onto `master`, not `main`.
- **Pre-existing `manifest.txt`**: a remote that already has a stale
  `manifest.txt` — it must be overwritten, and the other tracked files must
  survive byte-for-byte.
- **`ssh://` URL with an explicit port** (port 2222): host-key pinning must
  still pass strict checking on that port.
- **Messages containing spaces**, and **repeated runs**: running the same
  case again must still succeed (the sync is re-runnable; the remote history
  simply grows).

## Constraints

- No network access beyond the loopback SSH server.
- Do not modify `/srv/git`, `/etc/ssh`, or the `deploy` account. The grader
  checks the server configuration is unchanged (password-only auth intact)
  and drives hidden remotes through it.
- Do not hard-code to the visible remote: the same script must work for any
  `/srv/git/<name>.git` on this host, port 22 or 2222, any default branch.
- The verifier runs `bash /app/sync.sh` unchanged on hidden inputs.
