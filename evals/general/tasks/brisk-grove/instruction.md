# MDS single-node cluster bring-up

You are operating a single-node **MDS** (a small distributed store) sandbox plus
a lightweight SLURM-style scheduler emulator and an MDS job-launcher frame work.
Your job: bring the whole stack up by editing one site config, generating a few
small artifacts, and wiring a startup pipeline. Everything you create must live
under `/app` and be discoverable exactly where this document says.

There is no mystery here: the environment already ships the daemon program, the
dependent gateway server, the SLURM stand-in, and the launcher resolver. Your
job is to **configure them correctly and start them**, and to write the few glue
artifacts the operations runbook requires.

---

## The stack you control

| Component | Location | Role |
|-----------|----------|------|
| Site config | `/app/config/core.xml` | XML that defines the node address, RPC port, and complementary role bindings |
| Daemon jar | `/app/mds/daemon.jar` | `org.mds.Daemon`; a JVM daemon started once per role with a role argument |
| Gateway server | `/app/bin/gateway.py` | a long-lived dependent service the cluster depends on |
| Gateway client | `/app/bin/client_check.py` | a client compatible with the gateway |
| SLURM stand-in | `/opt/mdsl/bin/sinfo` | prints `TOTAL=N IDLE=M` for the current cluster state |
| Launcher resolver | `/opt/mdsl/bin/mdsl-resolve` | resolves a **named** launcher from your launcher config |
| SLURM state | `/opt/mdsl/state/nodes.json` | `{"total": N, "idle": M}` — may be rotated by the grader |

None of these source files need editing. You only edit `/app/config/core.xml`
and you only *create* the deliverables listed below.

---

## 1. Edit the site config — `/app/config/core.xml`

The file ships with placeholder (empty) values. Fill in the real ones:

| Property | Required value |
|----------|----------------|
| `mds.address` | `127.0.0.1` |
| `mds.rpc.port` | `18021` |
| `mds.binding.primary` | `namenode` |
| `mds.binding.data` | `datanode` |
| `mds.binding.secondary` | `journal-node` |

These values are what the cluster is told to listen on. The daemons and gateway
*become unequipable because they read this file*, so an empty or typo/uenced
value makes the roles fail to come up. Keep the file valid XML. The daemon binds
`primary` on `:18021`, `data` on `:18022`, `secondary` on `:18023`, and the
gateway listens on `:18031` (= rpc port + 10).

## 2. Write the boot script — `/app/start.sh`

An executable Bash script (shebang, `chmod +x`). Running `/app/start.sh` must:

1. **Start the gateway first and wait for its readiness signal.**
   Launch the long-lived dependent server:
   ```bash
   python3 /app/bin/gateway.py &
   ```
   then **poll** `/app/run/gateway.ready` (created by the gateway once it is
   serving) until it appears. Give it a bounded time-out (at least 30 s) and
   fail loudly if it never becomes ready. This ordering is required — the
   cluster depends on the gateway, so never start the daemons before the
   gateway reports ready.
2. **Start and keep alive three JVM daemon roles** by launching the daemon jar
   once per role, in the background, from `/app/mds/daemon.jar`:
   ```bash
   java -cp /app/mds/daemon.jar org.mds.Daemon primary  &
   java -cp /app/mds/daemon.jar org.mds.Daemon data     &
   java -cp /app/mds/daemon.jar org.mds.Daemon secondary&
   ```
   Wait for each role's ready marker in `/app/run/` (`primary.ready`,
   `data.ready`, `secondary.ready`) with a bounded timeout, and fail if any
   never appears. Leave all three daemons running when `start.sh` returns.
3. **Verify the dependent server is reachable by a compatible client.** After
   the daemons are up, run the readiness check:
   ```bash
   python3 /app/bin/client_check.py
   ```
   and exit non-zero if it fails.
4. Print a final line `MDS_CLUSTER_UP` on success.

`start.sh` must be idempotent-ish: if it is already run and a role is running,
do **not** exit the script waits; it is acceptable to reuse the existing
ready markers. Do not kill running daemons.

## 3. Write the monitor generator — `/app/monitor_gen.sh`

An executable shell script. It must:

1. Query the cluster with `sinfo`:  resolve `$(/opt/mdsl/bin/sinfo)`. That emits
   ``TOTAL=<n> IDLE=<m>` (the node counts the SLURM stand-in knows about).
2. Compute `fraction = (total - idle) / total`, formatted to exactly **3**
   fractional digits (`printf '%.3f'`). When `total` is `0`, use `0.000`.
3. Write `/app/monitor.log` with **exactly one header line** and this byte-for-
   byte shape:

   ```
   # MDS CLUSTER MONITOR - 2026-04-09T13:37:11Z
   Node total: <T>
   Node idle: <M>
   LoadFraction: <F>
   ```

   - The header timestamp is the current UTC time in strict `YYYY-MM-DDTHH:MM:SSZ`
     (i.e. `date -u +%Y-%m-%dT%H:%M:%SZ`), and the header must appear **once**,
     on the very first line.
   - `<T>` `<M>` come from `sinfo`.
   - `<F>` is the 3-decimal fraction above.

Repeat-formatting mistakes fail this deliverable. Never hard-code the counts;
always read them from `sinfo`.

## 4. Add a named launcher config — `/app/launcher.yaml`

The job-launcher framework selects a launcher **by name**. Write a config that:

- sets top-level `selection: slurm`,
- defines a `launchers:` block whose `slurm` launcher has `_target:
  mdsl.launcher.SlurmLauncher`, with these params under it: `partition: batch`,
  `account: mdsl`, `cpus_per_task: 4`, and one optional custom `extra` key of
  your choice,
- keeps a `job:` block with `name: rank-pivot` and `nodes: 2` **exactly as-is**
  (the launcher config must not change the job submission fields).

The resolver is `/opt/mdsl/bin/mdsl-resolve /app/launcher.yaml slurm`. See
`mdsl-resolve --help`? (there is none — run it; it prints a `TARGET ...` line
and the resolved non-job params when the config is valid). Use the indicated
indentation (2 spaces per level) exactly; this framework is a strict,
small-subset YAML parser.

## 5. Record the runner's interpreter path — `/app/runner/settings.json`

Write a JSON object:
```json
{"interpreter": "/usr/bin/python3"}
```
The value must be the resolved absolute path to a Python 3 interpreter (get it
with `command -v python3`). It must be non-empty, point at an existing
executable, and that executable must answer version `3` when run.

## 6. Export the tool environment for fresh shells — `/app/env.sh` and your shell rc

Write `/app/env.sh` (an executable shell snippet) that exports:

```bash
export MDS_HOME=/opt/mdsl
export MDS_BIN=/opt/mdsl/bin
export MDS_LAUNCHER=slurm
export MDS_RPC_PORT=18021
```

Then you must **persist the export in your shell startup file** so that a fresh
interactive shell picks the variables up. Append to `$HOME/.bashrc` (create the
file if missing) a line that sources this snippet:

```bash
[ -f /app/env.sh ] && . /app/env.sh
```

Do not overwrite an existing `.bashrc` wholesale if one exists for append. The
grader asserts the four variables above are visible with those values in a shell
that has just sourced the startup file.

---

## What NOT to touch

- Do not modify the shipped program sources: `/app/mds/*`, `/app/bin/*`,
  `/opt/mdsl/bin/*`.
- Do not edit `/opt/mdsl/state/nodes.json` as part of deliverable steps; the
  grader rotates that file between runs to re-check your generator.
- Your scripts must be self-contained and, once written, must reproduce their
  outputs by **running** (not by `cat`ing precomputed answers).

## Success criteria (summary)

After you finish, from a fresh shell:

1. `/app/start.sh` returns 0, the three daemon roles stay alive, the RPC port
   `18021` listens, and the gateway answers its client with `MDS-GATEWAY-READY`.
2. `/app/monitor_gen.sh` regenerates `/app/monitor.log` in the exact header +
   node-count + fraction format, matching whatever `sinfo` reports.
3. `mdsl-resolve /app/launcher.yaml slurm` succeeds and reports
   `TARGET mdsl.launcher.SlurmLauncher` with the four params and unchanged job
   fields.
4. `/app/runner/settings.json` holds a resolvable python3 path.
5. The four env vars (home, bin, launcher, rpc port) are visible in a fresh
   shell that has sourced the startup rc.

Do not stop any daemon or the gateway before you finish.