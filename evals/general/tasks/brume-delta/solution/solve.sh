#!/bin/bash
# Oracle for tasks/brume-delta (executes-deliverable).
# Fills in the two site-config deliverables (the real work), then smoke-tests
# them by ACTUALLY bringing up the cluster and running the client. Never
# reads /tests.
set -eu

mkdir -p /app/conf /app/run /app/data

# ---- 1. cluster-level site config -----------------------------------------
cat > /app/conf/core-site.xml <<'XML'
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://127.0.0.1:19310</value>
  </property>
</configuration>
XML

# ---- 2. node-level site config (complementary namenode/datanode) -----------
cat > /app/conf/hdfs-site.xml <<'XML'
<configuration>
  <property>
    <name>dfs.namenode.rpc-address</name>
    <value>127.0.0.1:19310</value>
  </property>
  <property>
    <name>dfs.datanode.address</name>
    <value>127.0.0.1:19311</value>
  </property>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
  <property>
    <name>dfs.permissions.enabled</name>
    <value>false</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/app/data/namenode</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>/app/data/datanode</value>
  </property>
</configuration>
XML

# ---- 3. smoke: bring the cluster up on the configured ports ----------------
pkill -f "dfsnode.py" 2>/dev/null || true
rm -f /app/run/namenode.ready /app/run/datanode.ready
rm -rf /app/data/namenode /app/data/datanode
mkdir -p /app/data/namenode /app/data/datanode

python3 /opt/shoredfs/dfsnode.py namenode >/tmp/shoredfs_nn.log 2>&1 &
NN=$!
for i in $(seq 1 60); do
    [ -f /app/run/namenode.ready ] && break
    kill -0 "$NN" 2>/dev/null || { echo "smoke: namenode died" >&2; cat /tmp/shoredfs_nn.log >&2; exit 1; }
    sleep 0.5
done
[ -f /app/run/namenode.ready ] || { echo "smoke: namenode never ready" >&2; exit 1; }

python3 /opt/shoredfs/dfsnode.py datanode >/tmp/shoredfs_dn.log 2>&1 &
DN=$!
for i in $(seq 1 60); do
    [ -f /app/run/datanode.ready ] && break
    kill -0 "$DN" 2>/dev/null || { echo "smoke: datanode died" >&2; cat /tmp/shoredfs_dn.log >&2; exit 1; }
    sleep 0.5
done
[ -f /app/run/datanode.ready ] || { echo "smoke: datanode never registered" >&2; exit 1; }

# ---- 4. smoke: client round-trip through the configured cluster ------------
got="$(python3 /opt/shoredfs/dfsclient.py --config-dir /app/conf --ops /app/examples/smoke_ops.txt)"
want='PUT gauge.river OK
GET gauge.river brume delta level 41 cm
PUT tide.idx OK
GET tide.idx high 07:42Z
LIST gauge.river,tide.idx'
if [ "$got" != "$want" ]; then
    echo "smoke: client output mismatch" >&2
    printf '%s\n' "$got" >&2
    kill "$NN" "$DN" 2>/dev/null || true
    exit 1
fi

kill "$NN" "$DN" 2>/dev/null || true
wait "$NN" "$DN" 2>/dev/null || true
pkill -f "dfsnode.py" 2>/dev/null || true
rm -f /app/run/namenode.ready /app/run/datanode.ready
rm -rf /app/data/namenode /app/data/datanode

echo "brume-delta deliverables written and smoke-tested:"
ls -l /app/conf/core-site.xml /app/conf/hdfs-site.xml
