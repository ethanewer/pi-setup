#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    cat << 'EOF' > /home/user/libs.csv
core,50
math,30
net,25
ui,80
db,120
crypto,45
EOF
rm -rf /home/user/.setup_tmp
