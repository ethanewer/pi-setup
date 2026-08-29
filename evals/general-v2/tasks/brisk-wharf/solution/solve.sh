#!/usr/bin/env bash
# brisk-wharf oracle: place the two code deliverables, bring up the cluster
# helpers, and run the full visible bundle (which lays down /app/markers).
set -euo pipefail

cp /solution/serve.py   /app/serve.py
cp /solution/mpi_main.c /app/mpi_main.c
chmod +x /app/serve.py

mkdir -p /app/markers/ /app/out

# Compile the two C helpers (protocol server + MPI aggregator).
gcc /app/protocol/server.c -o /app/protocol_server -lssl -lcrypto
mpicc -O2 /app/mpi_main.c -o /app/mpi_agg

# Bring up everything for the visible scenario: gloo, MPI, netflow, protocol,
# S3 bucket, and mailing list.
python3 /app/serve.py run-all

# Self check: parallel MPI == serial MPI on the visible fragments.
cat /app/out/ser/flows.rank*.txt | sort > /tmp/ser.txt
cat /app/out/par/flows.rank*.txt | sort > /tmp/par.txt
diff /tmp/ser.txt /tmp/par.txt >/dev/null
echo "oracle parallel==serial OK"

echo "ORACLE DONE"