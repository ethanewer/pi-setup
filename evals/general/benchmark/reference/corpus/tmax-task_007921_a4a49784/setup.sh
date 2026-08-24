#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip cargo
    # Create the user
    # Create data directory and logs.csv
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/logs.csv
id,group_id,content
1,100,XxYyZz
2,,XyzXyzXyz
3,200,hello world
4,,zzZZzz
5,105,xYxYxYxY
EOF
    # Create the Rust project
    cd /home/user
    cargo new log_pipeline
    # Ensure correct permissions
rm -rf /home/user/.setup_tmp
