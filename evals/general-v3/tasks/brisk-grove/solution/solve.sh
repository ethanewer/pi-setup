#!/bin/bash
# Oracle for tasks/brisk-grove (executes-deliverable).
#
# Does the real bring-up work: edits the cluster site config, writes every
# operator deliverable, and then ACTUALLY RUNS the pipelines (start.sh boots the
# dependent gateway + three JVM daemons; monitor_gen.sh emits monitor.log) so
# every output is produced by executing the work. Never reads / tests.
set -eu

mkdir -p /app/config /app/run /app/runner

# ---- 1. cluster site configuration (the designated address+port+bindings) ----
cat > /app/config/core.xml <<'XML'
<configuration>
  <property>
    <name>mds.address</name>
    <value>127.0.0.1</value>
  </property>
  <property>
    <name>mds.rpc.port</name>
    <value>18021</value>
  </property>
  <property>
    <name>mds.binding.primary</name>
    <value>namenode</value>
  </property>
  <property>
    <name>mds.binding.data</name>
    <value>datanode</value>
  </property>
  <property>
    <name>mds.binding.secondary</name>
    <value>journal-node</value>
  </property>
</configuration>
XML

# ---- 2. boot script: gateway-first, wait readiness, then three jvm daemons ----
cat > /app/start.sh <<'SH'
#!/bin/bash
set -u
mkdir -p /app/run

is_up() { # role
  [ -f "/app/run/$1.ready" ] || return 1
  [ -f "/app/run/$1.pid" ] || return 1
  kill -0 "$(cat "/app/run/$1.pid" 2>/dev/null)" 2>/dev/null
}

wait_ready() { # role timeout_sec
  local role="$1" n="$2" i
  for i in $(seq 1 "$n"); do
    [ -f "/app/run/$role.ready" ] && return 0
    sleep 1
  done
  return 1
}

# (1) long-lived dependent server first, wait for its readiness signal
if is_up gateway; then
  echo "gateway already up"
else
  python3 /app/bin/gateway.py &
  if ! wait_ready gateway 45; then
    echo "gateway never became ready" >&2
    exit 1
  fi
fi

# (2) three JVM daemon roles, kept alive.
for role in primary data secondary; do
  if is_up "$role"; then
    echo "$role already up"
    continue
  fi
  java -cp /app/mds/daemon.jar org.mds.Daemon "$role" &
  if ! wait_ready "$role" 45; then
    echo "$role failed to become ready" >&2
    exit 1
  fi
done

# (3) a compatible client verifies the dependent server is reachable.
python3 /app/bin/client_check.py || { echo "gateway client check failed" >&2; exit 1; }

echo "MDS_CLUSTER_UP"
SH

# ---- 3. monitor generator: query sinfo, emit exact-format monitoring log ----
cat > /app/monitor_gen.sh <<'SH'
#!/bin/bash
set -u
out="$(/opt/mdsl/bin/sinfo)"
total="$(printf '%s' "$out" | sed -n 's/.*TOTAL=\([0-9][0-9]*\).*/\1/p')"
idle="$(printf '%s' "$out" | sed -n 's/.*IDLE=\([0-9][0-9]*\).*/\1/p')"
if [ -z "$total" ] || [ -z "$idle" ]; then
  echo "monitor_gen: could not parse sinfo output: $out" >&2
  exit 1
fi
frac="$(python3 - "$total" "$idle" <<'PY'
import sys
t, i = int(sys.argv[1]), int(sys.argv[2])
print("0.000" if t <= 0 else "%.3f" % ((t - i) / t))
PY
)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "# MDS CLUSTER MONITOR - $stamp"
  echo "Node total: $total"
  echo "Node idle: $idle"
  echo "LoadFraction: $frac"
} > /app/monitor.log
SH

# ---- 4. named launcher config (SLURM launcher selectable by name) ----
cat > /app/launcher.yaml <<'YAML'
selection: slurm
launchers:
  slurm:
    _target: mdsl.launcher.SlurmLauncher
    partition: batch
    account: mdsl
    cpus_per_task: 4
    extra: sweep
job:
  name: rank-pivot
  nodes: 2
YAML

# ---- 5. runner interpreter path ----
INTERP="$(command -v python3)"
printf '{"interpreter": "%s"}\n' "$INTERP" > /app/runner/settings.json

# ---- 6. tool environment exports + persist in the shell startup file ----
cat > /app/env.sh <<'SH'
#!/bin/bash
export MDS_HOME=/opt/mdsl
export MDS_BIN=/opt/mdsl/bin
export MDS_LAUNCHER=slurm
export MDS_RPC_PORT=18021
SH

if [ -f "$HOME/.bashrc" ]; then
  line="[ -f /app/env.sh ] && . /app/env.sh"
  if ! grep -qF '/app/env.sh' "$HOME/.bashrc"; then
    printf '\n# MDS tool environment (added by operator)\n%s\n' "$line" >> "$HOME/.bashrc"
  fi
else
  printf '# MDS tool environment (added by operator)\n[ -f /app/env.sh ] && . /app/env.sh\n' > "$HOME/.bashrc"
fi

chmod +x /app/start.sh /app/monitor_gen.sh /app/env.sh

# ---- RUN the work: bring up the cluster and generate the monitoring log ----
bash /app/start.sh
bash /app/monitor_gen.sh
echo "oracle complete"