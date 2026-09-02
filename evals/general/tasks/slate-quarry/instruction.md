# slate-quarry — nightly rotation through the configured sudo policy

You are the on-call rotation operator for the *slate-quarry* snapshot
service. The box runs a narrow, passwordless sudo policy for the
unprivileged operator account `dana` (member of group `opscrew`):

```
dana ALL=(root) NOPASSWD: /usr/local/bin/snapshotctl, /usr/bin/shred
```

Two privileged effects are needed for tonight's rotation, and **both are
only reachable by invoking the allowed binaries through `sudo` as `dana`**:

1. The snapshot tool `/usr/local/bin/snapshotctl` (root-owned) mints seal
   files inside the root-only runtime gate `/var/lib/snapshotd/gate/`
   (mode 0700, owned by root). `dana` has no write access there without
   escalation. Its only useful subcommands are:
   - `snapshotctl seal <name>` — writes `<name>.seal` into the gate
     containing `snapshotd-seal:v1:<name>:<sha256>` (the sha256 is taken
     over the literal string `snapshotd-seal:v1:<name>`).
   - `snapshotctl verify <name>` — exits 0 iff the seal exists and is
     exactly current.
2. `/usr/bin/shred` — used with `-u` to destroy the protected ledger file
   `/opt/quarry-vault/rotating/ledger.bin` (root-owned, mode 0600, in a
   mode-0711 root-owned directory: searchable but not listable, and the file
   itself is only writable/readable by root) before the next cycle.

## Deliverables (both required)

1. `/app/ops.sh` — an executable bash script that performs the whole
   rotation (operations 1 and 2 below) and writes the report (deliverable
   2). The grader executes it **as the unprivileged user `dana`**:

   ```
   su -s /bin/bash dana -c 'bash /app/ops.sh'
   ```

   so the script runs with **no root powers of its own**: every privileged
   effect must be obtained through the configured passwordless sudo rule
   shown above. Do not rely on being root, and do not use any command the
   sudo policy does not allow for the privileged steps.

2. `/app/ops-report.txt` — the report your script writes when it runs as
   `dana`. It must be non-empty and contain:
   - a first line starting with `slate-quarry ops report - `;
   - a line containing the label `SEAL` and the literal command
     `snapshotctl seal nightly-rotator`;
   - a line containing the label `DESTROY` and the literal command
     `shred -u /opt/quarry-vault/rotating/ledger.bin`.

## Required operations

1. **Mint the rotation seal**: as `dana`, via sudo, run
   `sudo /usr/local/bin/snapshotctl seal nightly-rotator`. The file
   `/var/lib/snapshotd/gate/nightly-rotator.seal` must afterwards exist,
   be owned by `root`, contain the exact current seal body, and the gate
   directory must be mode 0700 owned by root.
2. **Destroy the protected ledger**: as `dana`, via sudo, run
   `sudo /usr/bin/shred -u /opt/quarry-vault/rotating/ledger.bin`. After
   the run the file must be gone. The vault directory
   `/opt/quarry-vault/rotating` must remain mode 0711 owned by root.

## Constraints & edge cases

- `/app/ops.sh` must be **idempotent**: the grader runs it several times,
  including after wiping the gate directory, after replacing the ledger
  file with new content, and after leaving a stale/bogus gate behind
  (possibly with wrong ownership). Every run must converge to the exact
  end-state above and exit 0.
- `snapshotctl seal` fixes the gate ownership/mode itself when run as
  root — reuse it rather than trying to touch the gate directly.
- Do not modify `/etc/sudoers.d/quarry`, `/usr/local/bin/snapshotctl`, or
  any permission under `/var/lib/snapshotd` or `/opt/quarry-vault` other
  than through the allowed escalated commands. The grader compares their
  pristine hashes and fails tampering.
- Do not read or modify anything under `/tests`.
- `/app/ops-report.txt` must end up owned/written by the `dana` run of
  the script (make the script rewrite it from scratch each run).
