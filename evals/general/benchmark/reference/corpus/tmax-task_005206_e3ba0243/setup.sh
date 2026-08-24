#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip openssl curl iproute2
rm -rf /home/user/.setup_tmp
