# brisk-atlas — multi-user developer box hardening & compliance

You are a DevOps engineer asked to bring a lightly-misconfigured multi-user
developer box into compliance for an internal audit. The box already has a
developer account `alice` (primary user for unprivileged access) and a group
`devteam`. Your job is to deliver a single idempotent fixer script
`/app/fix.sh` and an audit report `/app/audit.txt` that together implement the
changes below.

You are running as root in `/app`, but several of the required actions are
exercised **as the unprivileged user `alice`** on purpose (the audit wants to
prove that escalation is happening through the *configured* sudo policy, not
just because the box is running as root).

Read this contract carefully. The box is audited from a CLOSED starting state,
and then again after deliberately being degraded into weird states; the
deliverable must be safe to run repeatedly and must converge to the exact spec
from any of those states.

## Deliverables

1. `/app/fix.sh` — an executable `bash`/`sh` script implementing **all** of
   the hardening below. It must use the real OS tools and run to completion.
2. `/app/audit.txt` — a compliance report that `/app/fix.sh` WRITES by
   recording the real outcome of the operations it performs (stat/chmod/tar/
   sudo/setfacl lines). It must be non-empty and contain one line per section
   below (use the section's keyword as a label).

`/app/fix.sh` must never modify `/tests` or read it. Do not modify
`/opt/tools-scripts/*`, `/opt/objsvc/bridge`, or the account/group setup other
than what the spec asks for.

## The box's fixed facts

- Group `devteam` exists; `alice` is a member.
- `/opt/tools-scripts/deprecated.sh` and `/opt/tools-scripts/legacy.sh` are
  legacy shell scripts. They were committed with the execute bit set.
  **They must never be executed** — if you run them they will create a
  side-effect marker that fails the audit.
- `/opt/secret/root/client.bin` is a root-owned, mode-0600 artifact in a
  mode-0700 root-only vault. `alice` has NO direct write there.
- A sudoer rule grants `alice` the ability to run, without a password,
  `/usr/bin/rm` **and** the whole binary `/opt/objsvc/bridge` as root. This
  rule is intentionally broad (misconfigured): the bridge tool's only safe
  subcommand is `scan`; without the escalation it cannot write to the
  root-only runtime gate `/var/lib/brk/rootgate/`.
- `/app/portable-bucket` is a directory that starts out with a **private**
  ACL (only `alice` and a restrictive mask), i.e. the all-users principal has
  no access.
- `/home/alice/.bashrc` currently holds a single comment line.
- A source tree `/app/build-src` holds build artifacts whose metadata
  (permissions, ownership, timestamps) is deliberately messy.

## Required operations (implement all 7)

### 1. Shared setgid directory
Create `/srv/team/shared`, owned by group `devteam`, with the **setgid**
permission so that new children created inside it inherit group `devteam`.
Target: `drwxrwsr-x` owned by `devteam` group (mode with setgid set, group
write+execute). The directory must be absent-safe (create it if missing) and
group-safe (fix group if wrong).

### 2. Normalize archive metadata
Produce `/app/workspace.tar` from `/app/build-src` such that **every** member
carries normalized metadata:
- directory members have mode **700** (`drwx------`),
- regular file members have mode **600** (`-rw-------`),
- owner/group are normalized to `root/root`,
- every member's modification time is normalized to **2000-01-01 00:00:00**.
Rebuild it every run (the previous archive may be stale/wrong).

### 3. Strip legacy script execute bits
For both `/opt/tools-scripts/deprecated.sh` and
`/opt/tools-scripts/legacy.sh`:
- leave the file **in place**,
- remove ALL execute bits (must become non-executable),
- never execute them (no side-effect marker may ever appear),
- do not alter their bytes.

### 4. Remove the root-protected file, only after escalation
Remove the file `/opt/secret/root/client.bin`. You must do this by going
through the unprivileged user `alice` using the **allowed escalated command**
(the sudo `rm` rule) — not by just `rm`-ing it as root, and not by any
disallowed command.

### 5. Gain a capability via the misconfigured sudo rule
Invoke the sudo-allowed binary `/opt/objsvc/bridge` (as `alice`, through
sudo) with the `token` subcommand and the token name `atlas-client`. This
mints a capability token at `/var/lib/brk/rootgate/atlas-client.token` inside
the root-only directory — something `alice` could never do without the broad
sudo escalation.

### 6. Make the bucket readable by everyone (ACL)
Using the POSIX ACL commands, grant the all-users principal read access on
`/app/portable-bucket` and its contents so a fresh `getfacl` shows
`other::r--` for the bucket root. Only grant **read** — do not grant write.

### 7. Persist the tool environment in the shell rc
Append a block to `/home/alice/.bashrc` that **exports** the environment for
the box's compliance tool so any fresh interactive shell for `alice` sees it:
```
export BRISK_HOME=/opt/brisk
export BRISK_CTL=/opt/brisk/bin/ctl
export BRISK_HEADERS=/opt/brisk/share/headers
```
Do not duplicate the block if it already exists (keep the script idempotent).

## Constraints & edge cases (the audit also probes these)

- Every operation must be **idempotent**: running `/app/fix.sh` again on an
  already-fixed box, or on a box where targets are missing/locked-back, must
  converge to the exact spec above without erroring.
- The script must keep working if a target already exists in a wrong state
  (e.g. shared dir already present but with the wrong group / no setgid;
  scripts already re-marked executable; an old/wrong `workspace.tar` present;
  the root gate directory wiped; `audit.txt` missing).
- Never execute the legacy scripts; do not leave their side-effect markers.

## Output format
`/app/fix.sh` should be executable (`chmod +x`) and print a short status to
stdout on success. `/app/audit.txt` should start with a header line
`brisk compliance report - <timestamp>` and then contain one labeled line per
operation. The auditor will both run your script and read your report; the
real end-state is what matters, so the operations must genuinely happen.