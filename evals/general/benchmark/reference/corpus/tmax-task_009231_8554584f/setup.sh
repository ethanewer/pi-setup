#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 jq
    mkdir -p /home/user/analytics
    cat << 'EOF' > /home/user/analytics/network.csv
A,B,5
A,C,6
B,C,2
D,A,15
D,B,1
E,F,5
G,H,12
H,A,10
H,B,10
EOF
rm -rf /home/user/.setup_tmp
