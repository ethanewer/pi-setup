#!/bin/bash
# submit-spark.sh -- run the Spark workload via spark-submit in BOTH local[*]
# and standalone-cluster modes, and write one machine-readable runtime per run.
#
# Runtime contract for /app/runtimes.txt (overwritten each invocation):
#   MODE,DATE,ELAPSED_MS
#   LOCAL,2026-03-14,6214
#   CLUSTER,2026-03-14,7309
# MODE is LOCAL or CLUSTER-a standalone-cluster run, DATE is the date taken from
# a data file's name (per-file date attribution), ELAPSED_MS is the wall-clock
# duration of the spark-submit invocation.
set -euo pipefail

SPARK_PY=$(python3 -c "import os,pyspark;print(os.path.dirname(os.path.abspath(pyspark.__file__)))")
export SPARK_HOME="$SPARK_PY"
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
export SPARK_LOCAL_IP=127.0.0.1
export SPARK_MASTER_HOST=127.0.0.1
export SPARK_MASTER_WEBUI_PORT=8080
export SPARK_WORKER_WEBUI_PORT=8081
export SPARK_WORKER_CORES=1
export SPARK_WORKER_MEMORY=512m
export SPARK_DRIVER_MEMORY=512m
export SPARK_EXECUTOR_MEMORY=512m

EVENTS_DIR="${1:-/app/events}"
LOGS=/app/logs
mkdir -p "$LOGS"

echo "spark home: $SPARK_HOME"

# --- ensure standalone master (7077) + a worker are up, idempotently ---
master_up=0
if (exec 3<>/dev/tcp/127.0.0.1/7077) 2>/dev/null; then
    master_up=1
fi
if [ "$master_up" = "0" ]; then
    nohup "$SPARK_HOME/bin/spark-class" org.apache.spark.deploy.master.Master \
          --host 127.0.0.1 --port 7077 --webui-port 8080 \
          > "$LOGS/spark-master.out" 2>&1 &
    for _ in $(seq 1 40); do
        if curl -sf -o /dev/null http://127.0.0.1:8080 2>/dev/null; then
            break
        fi
        sleep 1
    done
fi

worker_up=0
if curl -sf -o /dev/null http://127.0.0.1:8081 2>/dev/null; then
    worker_up=1
fi
if [ "$worker_up" = "0" ]; then
    nohup "$SPARK_HOME/bin/spark-class" org.apache.spark.deploy.worker.Worker \
          --webui-port 8081 spark://127.0.0.1:7077 \
          > "$LOGS/spark-worker.out" 2>&1 &
    for _ in $(seq 1 40); do
        if curl -sf -o /dev/null http://127.0.0.1:8081 2>/dev/null; then
            break
        fi
        sleep 1
    done
fi

# date from the first per-date events file (per-file date attribution)
DATE=$(ls "$EVENTS_DIR" | sed -n 's/\(.*\)_events\.log/\1/p' | head -n1)
[ -n "$DATE" ] || DATE="2026-03-14"

rm -f /app/runtimes.txt

# --- LOCAL run ---
t0=$(($(date +%s%N)/1000000))
"$SPARK_HOME/bin/spark-submit" --master local[2] --driver-memory 512m \
    /app/spark_job.py "$EVENTS_DIR" \
    > "$LOGS/spark-local.out" 2> "$LOGS/spark-local.err"
t1=$(($(date +%s%N)/1000000))
echo "LOCAL,$DATE,$((t1-t0))" >> /app/runtimes.txt

# --- STANDALONE CLUSTER run ---
t0=$(($(date +%s%N)/1000000))
"$SPARK_HOME/bin/spark-submit" --master spark://127.0.0.1:7077 --driver-memory 512m \
    --executor-memory 512m /app/spark_job.py "$EVENTS_DIR" \
    > "$LOGS/spark-cluster.out" 2> "$LOGS/spark-cluster.err"
t1=$(($(date +%s%N)/1000000))
echo "CLUSTER,$DATE,$((t1-t0))" >> /app/runtimes.txt

echo "runtimes:"
cat /app/runtimes.txt