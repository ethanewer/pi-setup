# quiet-keel — unlock the service accounts

You are the operator of the **quiet-keel** batch host. Three service accounts
were provisioned with shells that prevent login, and the on-call runbook now
requires one of them to be unlocked. Everything lives under `/app`.

Fixed inputs (do **not** modify them):

- `/app/requirement.txt` — the runbook entry: a `user=` line and a `shell=`
  line naming the account to unlock and the shell it must end up with.
- `/app/notes.md` — operator notes (context only).

## Deliverables (both required)

1. `/app/set_shell.sh` — a reusable, **idempotent** shell script:

   ```
   /app/set_shell.sh <username> <new_shell>
   ```

   It must **permanently change the account's default login shell** in the
   user database (e.g. via `usermod`, `chsh`, or a careful `/etc/passwd`
   edit), so that afterwards `getent passwd <username>` reports `new_shell`
   as the login-shell field. Requirements:

   - The change must be **persistent**: it lives in the real account
     database files, not in any transient session state.
   - **Validate the target shell**: `new_shell` must be an existing,
     executable file. If it is not, print an error to stderr, change
     nothing, and exit non-zero.
   - **Validate the user**: the account must exist. If it does not, print an
     error to stderr, change nothing, and exit non-zero.
   - **Change only the shell field**: uid, gid, home directory, GECOS and
     the username itself must be untouched.
   - Running it twice with the same arguments is safe (idempotent).

2. `/app/answer.txt` — the outcome of applying the runbook entry: execute
   `/app/set_shell.sh` with the user and shell named in
   `/app/requirement.txt`, then record the result as a single line of the
   form:

   ```
   <username>:<new_shell>
   ```

   e.g. `svc-bot:/bin/dash` (with a trailing newline).

## Grading

The verifier executes `/app/set_shell.sh` on the visible runbook entry and on
**hidden** (user, shell) cases — including invalid ones that must fail
cleanly — and checks the account-database lookup (`getent passwd`) reports the
requested shell while every other account field is unchanged. A script that
"installs" the shell but never records it as the account's default login shell
will fail.
