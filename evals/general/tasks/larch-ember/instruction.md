# larch-ember — seal the backup appliance through the configured escalation path

You administer a small backup appliance. The appliance's sealing credentials
may only be minted by the **unprivileged service account `ops`**, and `ops` can
elevate exactly one way: a sudo policy that lets it run the sealing tool
`/usr/local/bin/sealctl` **as root without a password** — and nothing else.
Your job is to deliver an idempotent provisioning script that brings the
sealing state to the required end state **using that escalation path**, plus a
provisioning report.

## Fixed facts about the box

- User `ops` exists (uid in the 2100s, primary group `opscrew`).
- The root-only seal vault `/var/lib/sealvault/` is a directory owned by
  `root:root` with mode `0700`. `ops` has no direct write access there.
- `/etc/sudoers.d/sealbox` contains exactly one rule:
  `ops ALL=(ALL:ALL) NOPASSWD: /usr/local/bin/sealctl`
  This rule must remain byte-identical when you are done.
- `/usr/local/bin/sealctl` is a root-owned Python tool. Its subcommands:
  - `seal <name> <value>` — mints `/var/lib/sealvault/<name>.seal`, mode `0640`,
    owner `root:opscrew`. `<name>` must match `[a-z0-9][a-z0-9-]{0,31}`; `<value>`
    must be exactly 4 lowercase hex digits. Every seal operation appends a line
    to the internal journal `/var/lib/sealvault/.journal` recording the name and
    the invoking `SUDO_USER`.
  - `prune <keep1> <keep2> ...` — deletes every `*.seal` in the vault whose name
    is not one of the `keep` arguments, and journals the prune.
  - `list` — prints the seal names currently in the vault.
  - `verify <name>` — re-computes the seal's checksum; prints `OK`/`BAD`.
  - Any bad invocation exits non-zero with a message on stderr.
- Without elevation `ops` cannot write into `/var/lib/sealvault` at all, so the
  only way to mint, re-mint, or prune seals is through the sudo rule.

## Deliverables

1. `/app/provision.sh` — an **executable** `bash`/`sh` script that brings the
   box to the required end state (below). It must:
   - run to completion with exit status 0 when invoked **as root** (the auditor
     runs it as root; it may also be run from any state),
   - perform **all privileged sealing work as the user `ops` through the
     configured sudo rule** (i.e. via something like
     `runuser -u ops -- sh -c 'sudo -n /usr/local/bin/sealctl ...'`),
     never by writing the vault files directly as root,
   - be **idempotent**: running it again on an already-provisioned box, or on a
     degraded box (required seal missing; a seal present with wrong content or
     wrong ownership; the whole vault directory deleted; stale seals present)
     must converge to the exact end state below without errors,
   - never modify `/etc/sudoers.d/sealbox` or anything under `/tests`.

2. `/app/provision.log` — a text report that `/app/provision.sh` (re)writes on
   every run. It must be non-empty and must contain, at minimum:
   - the literal token `sealctl`,
   - the names `ledger-primary` and `ledger-audit` on their own lines or inside
     lines describing each sealing operation.

## Required end state

- `/var/lib/sealvault/` exists, owned `root:root`, mode `0700`.
- `/var/lib/sealvault/ledger-primary.seal` mints value **`7f3a`**.
- `/var/lib/sealvault/ledger-audit.seal` mints value **`9c02`**.
- Both seal files are owned `root:opscrew` with mode `0640`, and their content is
  exactly the format `sealctl` produces (minting them with the tool guarantees
  this; the checksum line is `sha256("<name>=<value>")` truncated to 16 hex
  characters).
- **No other `*.seal` file** exists in the vault — stale seals from older runs
  must be removed (use the tool's `prune` subcommand through the same
  escalation path).
- The journal `/var/lib/sealvault/.journal` contains, for each of
  `ledger-primary` and `ledger-audit`, at least one entry proving the seal was
  minted by the invoking user `ops` through sudo (the tool writes this itself
  when invoked correctly).
- `/etc/sudoers.d/sealbox` is unchanged.

## Constraints

- Do not modify `/usr/local/bin/sealctl`, `/etc/sudoers.d/sealbox`, or the
  account setup.
- The verifier will **run `/app/provision.sh` itself** after degrading the box
  into several different wrong states, then check the end state, so the script
  must genuinely converge — not just check boxes once.
- No network access. Use only tools present on the box (`sudo`, `runuser`/`su`,
  coreutils).
