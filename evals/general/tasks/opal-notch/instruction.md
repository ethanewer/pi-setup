# opal-notch — drop-hub login shell provisioning

You are the site operator for **opal-notch**, an internal drop-hub relay box.
The relay team just shared a policy that locks down which login shell each
local service account is allowed to use. Your job is to make the account
database on this box agree with the policy — permanently.

The box is a minimal Debian-based container (Python 3.12 available as
`python3`). You are root. There is **no network access** and **no systemd**;
work entirely with local tools (`usermod`, `chsh`, `getent`, …). Work in
`/app`.

Fixed asset (do **not** modify it):

- `/app/shell_policy.json` — the shell policy you must apply. It is a JSON
  object with an `"accounts"` key mapping **username → required login shell**,
  e.g. `{"relqa": "/bin/bash"}`. Only accounts that actually exist on the box
  appear in policies, and every required shell is listed in `/etc/shells`.

## Deliverables (both required)

1. `/app/setup.sh` — a self-contained, **idempotent** bash script (safe to run
   any number of times, on any policy) that:
   - reads `/app/shell_policy.json`;
   - for every account listed there, sets that account's **default login
     shell** in the system account database so that a user-database lookup
     (`getent passwd <user>`) reports exactly the required shell as the login
     shell (last `:`-separated field of the passwd entry). Use the real
   account database tools — writing a copy of `/etc/passwd` somewhere else, or
   only creating an alias/wrapper, does **not** count;
   - writes `/app/shell_report.json` — a JSON object mapping each account
     listed in the policy to the login shell that `getent passwd <account>`
     actually reports **after** your changes;
   - exits 0 on success.

   Contract: `bash /app/setup.sh` (no arguments). The grader re-runs this
   script against **different hidden policy files** (written over
   `/app/shell_policy.json`), each listing existing local accounts and shells
   present in `/etc/shells`, and then queries the account database to confirm
   every account's login shell really changed. So: never hard-code account
   names, never hard-code the report contents, and never assume which shell an
   account currently has.

2. `/app/shell_report.json` — the report your script produces **when run on
   the provided policy**:
   ```
   bash /app/setup.sh
   ```

## Rules

- The fix must live in the real account database (`/etc/passwd` via
  `chsh`/`usermod`); an alias, an environment override, or an unchanged
  account fails.
- Idempotent: running `setup.sh` twice in a row must leave the system in the
  same state and exit 0 both times.
- Do **not** modify `/app/shell_policy.json` (the grader verifies its bytes).
- Do not read or modify `/tests` or `/solution`.
- Everything must be deterministic; no network access.