# vine-helix — Petal analysis node repair & provisioning

You are standing on a freshly-deployed **Petal analysis node** at the shared
research cluster. A botched rollout left the node in a broken state. Your job is
to repair **all** of the subsystems below and package the repairs into two
idempotent scripts plus one captured-output file. The verifier will (a) re-run
your configure script from a clean state, (b) check a hidden set of permission
trees through your permission-repair script, and (c) diff your captured banner.

## Deliverables

You must ship exactly three files in `/app`:

1. `/app/configure.sh` — an **executable**, **idempotent** (re-runnable) bash
   script that performs every repair described under *Configuration contract*.
   The verifier runs it again after your run; re-running must not error or leave
   anything in a worse state.
2. `/app/fixperms.sh` — an **executable** bash permission-repair script whose
   contract is described under *fixperms.sh contract*. It is invoked on
   independent input trees, including unusual ones.
3. `/app/dump.txt` — the verbatim terminal-ending banner (see *Capture the
   ending banner*).

## Accounts, groups, shared area

- System group **`petal`** exists (gid 4200).
- Account **`juna`** (a petal member) and **`broka`** (NOT a petal member) both
  exist.
- The team's shared area is `/app/shared`, created for group `petal`.

## Configuration contract (`/app/configure.sh`)

### 1. Enable password-based authentication
Account `juna`'s password-based login is currently **disabled** (its shadow
entry is locked). Enable it so that `juna` logs in with the password
**`PetalGrove-74Rook`**:
- set `juna`'s shell to a login shell, unlock the account, and set that
  password (a real password hash must be present in `/etc/shadow`; `crypt`
  verification of the secret must succeed, and the entry must not be locked
  `!`/`*`),
- enable `PasswordAuthentication yes` in the sshd config under
  `/etc/ssh/sshd_config.d/`.

### 2. Shared area: outsiders denied, group members allowed
- `/app/shared` (and its contents) must belong to group **`petal`**.
- The directory must have **group** read+execute (a mode like `750`/`770`), so
  group members can read `/app/shared/metrics/file1.csv` while **non-members**
  such as `broka` are **denied** read access to it.

### 3. Restore execute + read on the group's shell scripts
The files under `/app/shared/scripts/*.sh` lost their mode bits during the
rollout (some are literally mode `000`). Restore read **and** execute for them
(e.g. `0755`) so group members can run them. The scripts directory must remain
group-owned by `petal`.

### 4. Profile the python workloads with cProfile
Two slow workloads live at:
- `/app/jobs/digest_slow.py` (fast equivalent: `/app/jobs/digest_fast.py`)
- `/app/jobs/refine_slow.py` (fast equivalent: `/app/jobs/refine_fast.py`)

Profile **each** under cProfile, writing the stats the profiler emits to:
- `/app/prof/digest_slow.stats`, `/app/prof/digest_fast.stats`
- `/app/prof/refine_slow.stats`, `/app/prof/refine_fast.stats`

Then **read the recorded totals** and write `/app/prof/band.txt` with one line
per workload of the exact form:
```
digest: slow=<SECONDS> fast=<SECONDS> faster_ok=yes
refine: slow=<SECONDS> fast=<SECONDS> faster_ok=yes
```
The band is **accepted** when the fast total is below `1.0s` and clearly below
the slow total. (The fast variants are already the optimized implementations;
your job is to profile both, record the totals, and confirm the band.)

### 5. Run the bundled node trial checker
A Node runner is provided at `/app/check/runner.mjs`:

```
node /app/check/runner.mjs [trials] [solution] [out]
```

- It reads the visible trial map from `/app/check/trials.json` (layouts
  `alpha`, `beta`, `gamma`), re-derives the oracle turn count for each layout
  from the layout spec itself (see the runner source — `turns = 2*cells + 1`),
  and grades the submitted answers against it.
- Your submitted answers go in `/app/check/solution.json` (object mapping each
  layout id → your turn count).
- It writes a results report to `/app/results/results.json` containing a
  `summary` with `total`/`passed`/`failed` plus a `trials` array, and exits
  non-zero if any trial is FAIL.

Author the correct `solution.json` for the visible layouts, run the runner, and
**read** its results report to confirm `passed == total` (self-verification)
before finishing. The visible layout ids and their `cells` come from
`/app/check/trials.json`.

### 6. Remove configuration + process-id lifecycle files
Purge the leftover lifecycle files:
- `/app/registry/registry.conf`
- `/app/registry/gw.pid`

Both must be absent after configuration.

### 7. Running-task cleanup on cancellation
The cleanup worker `/app/cleanup/sweep.py` is **buggy**: its stop handler
(`SIGTERM`/`SIGINT`) calls `sys.exit()` immediately, so when a run is canceled
the still-in-flight bundle's cleanup never runs and the required marker
`cleanup-complete` is never written to `/app/cleanup/sweep.log`.

Fix the worker so that on cancellation it:
1. stops scheduling new bundles,
2. lets the in-flight bundle finish,
3. runs the cleanup handler — appending the single line
   `cleanup-complete bundle=<k>` to `/app/cleanup/sweep.log`,
4. only then exits `0`.

A provided driver `/app/cleanup/run_tester.sh` launches the sweep, cancels it
mid-run, and exits `0` **only** if the log contains `cleanup-complete`. Your
configuration must leave the worker correct so this driver passes each run.
You may fix `sweep.py` directly and/or encode the fix in `configure.sh` (so a
re-run reconstitutes it).

### 8. Capture the ending banner
`/app/finish.sh` prints a multi-line **terminal-ending banner** to stdout.
Capture it **verbatim** (byte-for-byte, no trimming, no paraphrasing, ending
with exactly one trailing newline) into `/app/dump.txt`. The verifier diffs
`/app/dump.txt` against a fresh run of `finish.sh`.

## fixperms.sh contract

```
/app/fixperms.sh <target-dir>
```

Restore **read + execute** permission bits on:
- every file named `*.sh` anywhere under `<target-dir>`, **and**
- every file under `<target-dir>` that already carries an execute bit for
  anyone (mode `0111` etc.)

Set each matched file to `0755`. **Do not touch** non-script files that have no
execute bit (their modes must be preserved exactly). Behavior on edge cases
(which the verifier exercises):

- a `<target-dir>` that does **not** exist → graceful no-op, exit `0`
- an **empty** directory → no-op, exit `0`
- scripts with odd modes (`000`, read-only `0400`, execute-only `0111`),
  **nested** subdirectories, and mixed trees → matched files become readable
  and executable; non-scripts keep their modes.
- the repair is recursive across all subdirectories.

`fixperms.sh` must never fail or mutate unrelated files.

## Constraints

- Work as root (you are root). No systemd, no GPU, no X.
- Do **not** modify `/tests`, and do not read the verifier or hidden cases.
- The bundled fixtures under `/app` (runner.mjs, trials.json, finish.sh,
  jobs, registry, cleanup/run_tester.sh) are part of the environment — you may
  **fix** `sweep.py` but must not otherwise delete or rewrite fixtures as a
  shortcut.
- `configure.sh` must be idempotent: run it twice in a row without error.
- Confirm everything locally: run `bash /app/configure.sh`, then re-run it,
  verify `/app/results/results.json` shows all PASS, `band.txt` says
  `faster_ok=yes`, `run_tester.sh` exits 0, `fixperms.sh` behaves sensibly on a
  scratch dir, and `/app/dump.txt` matches `finish.sh`'s output. Then you are
  done.

## Deliverables recap

- `/app/configure.sh` (executable, idempotent)
- `/app/fixperms.sh` (executable)
- `/app/dump.txt`
