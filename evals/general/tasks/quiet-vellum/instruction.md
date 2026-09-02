# quiet-vellum: shell onboarding for service accounts

You are the operator of the **quiet-vellum** build node. The node runs several
service accounts that were provisioned with a locked shell
(`/usr/sbin/nologin`). The onboarding runbook requires that an account's
**default login shell** actually be changed, permanently, so that a
**user-database lookup** (`getent passwd <user>`) reports the new shell — not
merely that the shell binary is present on the box.

Working directory: `/app`. You are root. There is no systemd; use the
standard account-management tools (`usermod`, `chsh`) or edit the persistent
account database directly.

## Deliverables (both required, under `/app`)

1. `/app/provision.sh` — a reusable, **idempotent** shell script with this
   interface:

   ```
   bash /app/provision.sh <username> <shell>
   ```

   Requirements:

   - It must set the **default login shell** of the existing local account
     `<username>` to `<shell>` **persistently** — i.e. the system user
     database (`/etc/passwd` via `getent passwd <username>`) must report
     `<shell>` in field 7 afterwards, and that must remain true for any later
     process (no session-only state).
   - It must be **idempotent**: running it several times with the same
     arguments leaves the account in the same correct state and exits 0 each
     time, even when the shell is already set.
   - It must **generalize**: the grader runs it with different existing local
     users and different installed shells (see the account list below), so do
     not hard-code one account or one shell path.
   - It must exit 0 on success. Do not print a usage banner to stdout on the
     success path (stderr diagnostics are fine).

2. `/app/shell_report.json` — a JSON report of the onboarding result for the
   **visible case**, with exactly these two keys:

   ```json
   {"user": "nightlog", "default_shell": "/bin/dash"}
   ```

   It must reflect the **real** state of the account database at the end of
   your work: after you run your provisioner for the visible case, the
   `default_shell` value must equal field 7 of `getent passwd nightlog`.

## The visible case (what you must actually do now)

The image ships these local accounts, all currently locked to
`/usr/sbin/nologin`:

- `nightlog`
- `quartermaster`
- `coxswain`

For the visible case, change the default login shell of **`nightlog`** to
**`/bin/dash`** (installed in the image) by running your provisioner:

```
bash /app/provision.sh nightlog /bin/dash
```

Then write `/app/shell_report.json` as specified above.

## Grading

The verifier, on a fresh container:

- runs `bash /app/provision.sh nightlog /bin/dash` (twice, to check
  idempotency) and confirms the user-database lookup reports `/bin/dash`;
- checks `/app/shell_report.json` is exactly consistent with the real
  `getent passwd nightlog` lookup;
- runs `/app/provision.sh` on **hidden account/shell pairs** (the same
  accounts, other installed shells such as `/bin/sh`) and confirms each
  lookup reports the requested shell.

## Constraints

- Do not read or modify `/tests` or `/solution`.
- No network access. Standard tools only.
- Everything must be deterministic and re-runnable from a fresh process.
