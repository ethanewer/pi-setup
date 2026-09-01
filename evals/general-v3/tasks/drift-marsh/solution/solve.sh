#!/bin/bash
# Oracle for drift-marsh (executes-deliverable).
# Does the real operator work: fills in both Kelpline property files, writes
# the boot script, then ACTUALLY RUNS it to bring the cluster up. Never reads
# /tests.
set -eu

mkdir -p /app/conf /app/run

# ---- 1. core configuration: designated address + rpc port -------------------
cat > /app/conf/core.properties <<'PROPS'
# Kelpline core configuration (single-node store).
kelpline.node.address = 127.0.0.1
kelpline.rpc.port = 24418
PROPS

# ---- 2. site configuration: complementary roles + replication factor -------
cat > /app/conf/site.properties <<'PROPS'
# Kelpline site configuration (single-node store).
kelpline.role.master = namenode
kelpline.role.worker = datanode
kelpline.replication.factor = 1
PROPS

# ---- 3. boot script: launch both roles, wait bounded, fail loudly ----------
cat > /app/start_cluster.sh <<'SH'
#!/bin/bash
set -u

run_dir="${KELP_RUN_DIR:-/app/run}"
mkdir -p "$run_dir"

wait_ready() { # role timeout_sec
    local role="$1" limit="$2" i
    for i in $(seq 1 "$limit"); do
        [ -f "$run_dir/$role.ready" ] && return 0
        sleep 1
    done
    return 1
}

python3 /app/bin/kelp_daemon.py namenode &
python3 /app/bin/kelp_daemon.py datanode &

for role in namenode datanode; do
    if ! wait_ready "$role" 45; then
        echo "start_cluster: role $role never became ready in $run_dir" >&2
        exit 1
    fi
done

echo "KELP_CLUSTER_UP"
SH
chmod +x /app/start_cluster.sh

# ---- 4. real smoke run: boot the cluster for the default configuration -----
bash /app/start_cluster.sh

# Confirm both designated ports actually listen.
python3 - <<'PY'
import socket
for port in (24418, 24419):
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.close()
PY

echo "drift-marsh oracle done -> configs + start_cluster.sh, cluster is UP"
