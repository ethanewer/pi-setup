# Kelpline single-node store bring-up

You are the operator of a **Kelpline** single-node store sandbox. The store
daemon program is already shipped; what is missing is the configuration (the
two property files still carry empty placeholder values) and a boot script.
Bring the cluster up on its designated address and RPC port.

## The stack you control

| Component | Location | Role |
|-----------|----------|------|
| Core config | `/app/conf/core.properties` | node address + designated RPC port (UNCONFIGURED) |
| Site config | `/app/conf/site.properties` | complementary role bindings + replication factor (UNCONFIGURED) |
| Store daemon | `/app/bin/kelp_daemon.py` | shipped program — **do not modify** |

The daemon reads both property files from the configuration directory
(environment variable `KELP_CONF_DIR`, default `/app/conf`) and writes
`<role>.pid` / `<role>.ready` markers into the run directory
(environment variable `KELP_RUN_DIR`, default `/app/run`). A role whose
config is empty or wrong exits immediately with a diagnostic instead of
binding, so a miswritten value means the cluster never comes up.

## 1. Fill in the core config — `/app/conf/core.properties`

Keep the Java-properties format (`key = value`, `#` comments, blank lines
allowed) and set exactly:

| Property | Required value |
|----------|----------------|
| `kelpline.node.address` | `127.0.0.1` |
| `kelpline.rpc.port` | `24418` |

The namenode binds `address:24418`; the datanode binds `address:24419`
(rpc port + 1).

## 2. Fill in the site config — `/app/conf/site.properties`

| Property | Required value |
|----------|----------------|
| `kelpline.role.master` | `namenode` |
| `kelpline.role.worker` | `datanode` |
| `kelpline.replication.factor` | `1` |

These are the complementary namenode/datanode functions: the master role must
be `namenode` and the worker role must be `datanode` (the daemon validates
the exact strings), and single-node operation requires replication factor
exactly `1`.

## 3. Write the boot script — `/app/start_cluster.sh`

An executable Bash script (shebang, `chmod +x`). Running
`bash /app/start_cluster.sh` must:

1. Launch **both daemon roles** in the background:
   ```bash
   python3 /app/bin/kelp_daemon.py namenode &
   python3 /app/bin/kelp_daemon.py datanode &
   ```
   Let the environment flow through unchanged (the daemons honour
   `KELP_CONF_DIR` / `KELP_RUN_DIR` themselves — do not hardcode any port or
   address in the script).
2. Wait for each role's ready marker (`namenode.ready`, `datanode.ready`) in
   the run directory with a **bounded timeout of at least 30 seconds**, and
   **fail loudly** (non-zero exit, diagnostic on stderr) if a marker never
   appears.
3. On success print the single line `KELP_CLUSTER_UP` and exit `0`, leaving
   both daemon processes running.

If a role exits early (bad config), your script must not hang forever: it
must give up within its bounded timeout and exit non-zero.

## Constraints

- Do not modify `/app/bin/kelp_daemon.py` or the shipped placeholder
  structure beyond filling in the required values.
- Your configs and script must be generic: the grader re-runs
  `start_cluster.sh` against alternative Kelpline configuration directories
  (different designated ports, extra comments/whitespace) via `KELP_CONF_DIR`
  and `KELP_RUN_DIR`, so never assume `/app/conf` or port `24418` inside the
  script, and make sure a broken configuration directory makes the script
  exit non-zero.
- No network access is needed; Python 3.12 only.

## What the grader checks

1. The two property files carry exactly the designated values (parsed
   independently, `key = value` format).
2. `bash /app/start_cluster.sh` exits 0, prints `KELP_CLUSTER_UP`, both
   daemons stay alive with ready markers in `/app/run`, and TCP connects to
   `127.0.0.1:24418` (namenode) and `127.0.0.1:24419` (datanode) succeed.
3. Hidden configuration directories: for a valid alternative config the
   script boots the cluster and the roles listen on that config's designated
   rpc port and rpc port + 1; for a deliberately broken config the script
   exits non-zero instead of reporting success.
