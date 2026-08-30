#!/bin/bash
# Oracle for moss-kernel: install the Triton kernel module and the self-check,
# then RUN the self-check end-to-end under the CPU interpreter. Never reads
# /tests.
set -euo pipefail

install -m 0644 /solution/gated_ops.py /app/gated_ops.py
install -m 0755 /solution/selfcheck.py /app/selfcheck.py

python3 -u /app/selfcheck.py

echo "oracle ok"
