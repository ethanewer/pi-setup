# PRISM-null: shared-area ops handoff

You are the on-call systems engineer for **PRISM-null**, a small research grid.
A previous operator left the shared area and its services in a broken state, and
a booting telemetry service had its source removed from disk while still running.
Your job is to leave behind three **program deliverables** under `/app` and one
**evidence bundle** `/app/dump.txt`. The verifier runs your deliverables both on
the live `/srv/prism` area and on fresh hidden scenarios, so write the programs
generically (they take their target as arguments).

Work in `/app`. Everything you need is already installed. Do **not** stop or
kill the running telemetry service; you need it alive to recover its source.

## Users and the shared area

The machine has two non‑root users you may use to test access control:

- `meridian` — GROUP MEMBER. It belongs to group **`anchorline`**.
- `hopper` — OUTSIDER. It is **not** in `anchorline`.

The shared area is `/srv/prism`. It contains `bin/` (admin shell scripts) and
`data/` (relay records). Its permissions are currently broken: directories are
world‑open (`0777`) and the scripts in `bin/` have lost their execute and, in one
case, all permissions. There are also stale lifecycle files
(`/srv/prism/.relay.pid`, `/srv/prism/relay.bak`) that must not remain.

## Deliverable 1 — `/app/configure.sh`

A shell script, executable, usable as:

```
configure.sh [SHARED_DIR [GROUP]]        # e.g. configure.sh /srv/prism anchorline
```

With defaults `/srv/prism` and `anchorline`, it must be **idempotent** and do all
of the following:

1. **Deny non‑members.** Base and "other" columns for `SHARED_DIR` and every
   subdirectory must carry **no permissions** for `other` (i.e. the tree becomes
   groups‑only, `0770` on every directory), so anyone not in `GROUP` cannot
   list, read, or create inside the hierarchy.
2. **Preserve group script execution.** On the `bin` subarea under `SHARED_DIR`,
   add a **default access‑control list** whose **default mask is `rwx`** and whose
   default group entry is `group:GROUP:rwx`, and ensure the directory's effective
   ACL `mask` is `rwx` — so a group member's execute permission is never stripped.
3. **Enable password‑based authentication.** In `/etc/ssh/sshd_config`, make the
   `PasswordAuthentication` directive `yes` (currently `no`).
4. **Remove lifecycle files.** Delete any `*.pid` and `*.bak` regular files that
   live directly inside `SHARED_DIR` (this includes hidden dot‑files such as
   `.relay.pid`).

If `SHARED_DIR` is a **regular file** (not a directory), `configure.sh` must
print a message to stderr **and return non‑zero**, without modifying that file.
If `SHARED_DIR` does not exist it must create it before configuring.

## Deliverable 2 — `/app/fixperms.sh`

A shell script, executable, usable as:

```
fixperms.sh DIR
```

For every `*.sh` regular file directly inside `DIR` (first level only, not
recursive), restore permissions to **`0755`** (`rwxr-xr-x`): owner read/write/execute,
group read/execute, and read/execute for others — so group members can read and
run them. Non‑`*.sh` files must be left untouched. If `DIR` does not exist or
holds no `.sh` files, exit `0` (a no‑op) without error.

## Deliverable 3 — `/app/mapper.py`

Implement `normalize(items)` in a Python module named exactly `mapper.py` with
the following rule:

> Cast each item to str, strip surrounding whitespace, drop empty/whitespace‑only
> results, then deduplicate preserving **first‑occurrence order**.

Edge cases the verifier probes: empty input list → `[]`; integers, booleans and
`None` become their string forms (`"1"`, `"True"`, `"None"`); duplicates collapse
to the first occurrence; ordering is preserved; leading/trailing and inner
whitespace-only entries are dropped.

`mapper.py` must be importable (`from mapper import normalize`) and must also run
standalone. When run as:

```
python3 /app/mapper.py /path/examples.json
```

it must print, on two lines: (1) a JSON array of `normalize(input)` for each case
in the file's `cases` list, and (2) the word `all-match` if every output equals
that case's `expected`, else `mismatch`.

The file `/app/examples.json` already ships with the worked example cases.

**Before turning it in, run your `normalize` on every example in `/app/examples.json`
and confirm all outputs equal the expected values** — the verifier compares
against exactly that, and then re-runs `normalize` on fresh hidden inputs.

## Deliverable — `/app/dump.txt` (evidence bundle)

Produce a single text file `/app/dump.txt` containing the following **sections**
in this exact order, each delimited by a header line of the form
`====[NAME]====`, the body on the following lines until the next such header
(blank lines between sections optional):

```
====[SERVER_RECOVERY]====
<the full reconstructed source of the running telemetry service>
====[SECRET]====
<the secret string extracted from that source>
====[TRANSFORM]====
<one line: the JSON list of normalize() outputs for /app/examples.json>
====[TRANSFORM_OK]====
<the all-match / mismatch word from that run>
====[SUITE_TAIL]====
<the suite summary line of the targeted test run>
====[PROFILE_TOP]====
<the cProfile cumulative top lines for /app/prism_work.py>
====[TERMINAL_TAIL]====
<the final line of the running service's own boot log>
```

Details of each:

- **SERVER_RECOVERY / SECRET.** A live python process is running the script
  `telemetry.py` (its original path was `/tmp/prism-north/telemetry.py`), but
  that file has been **deleted from disk**. The process holds its own source open
  through a file descriptor, so the content survives only in the process's
  `/proc`. Find the live process (e.g. `ps auxw`, `pgrep -f telemetry.py`), list
  its `fd`s (`ls -l /proc/<pid>/fd`), locate the descriptor whose symlink points
  at the deleted file (`... (deleted)`), and read it (`cat /proc/<pid>/fd/N`).
  That reconstructed source contains a `SECRET = "..."` line and the actual body
  of the service. Write the whole recovered source into `SERVER_RECOVERY` and the
  secret as the **bare** value (unquoted) into `SECRET`. The verifier will
  independently recover the same source and cross‑check both sections. Pay
  attention: the secret value lives ONLY in that deleted‑but‑open source; there
  is no other copy on disk.

- **SUITE_TAIL.** Run the targeted suite:
  ```
  python3 -m pytest -q /app/qa/suite
  ```
  The suite summary line (the one ending in something like `8 passed ...`) is
  what must appear verbatim under `SUITE_TAIL`. The verifier re‑runs the same
  suite itself and compares the reported pass count to whatever you documented.

- **PROFILE_TOP.** Profile the provided workload with `cProfile` and record its
  top cumulative lines:
  ```
  python3 -m cProfile -o /tmp/pstats.out /app/prism_work.py
  python3 -c "import pstats; pstats.Stats('/tmp/pstats.out').strip_dirs()\\
              .sort_stats('cumtime').print_stats(5)"
  ```
  Copy the first cumulative-tally lines that mention the function `spin_tally`
  into `PROFILE_TOP`.

- **TERMINAL_TAIL.** The bootstrap service printed a single ending line to its
  boot log (`/tmp/prism-north/boot.log`) when it came up. Record that file's
  **last line verbatim** under `TERMINAL_TAIL`. The verifier reads the same last
  line and requires an exact match.

## Deliverable — scope

Only the three programs and `dump.txt` matter; you may create helper files
anywhere you like. `/app` fixtures you may read but must not modify:
`/app/examples.json`, `/app/prism_work.py`, `/app/qa/suite/`. When done,
`configure.sh` and `fixperms.sh` must run correctly as shown above.

Use `getfacl`/`setfacl`, `stat`, `runuser`/`su` freely. Remember: an outsider
(`hopper`) must be denied everything in the configured area and an `anchorline`
member (`meridian`) must be able to **read and execute** the scripts in `bin/`.