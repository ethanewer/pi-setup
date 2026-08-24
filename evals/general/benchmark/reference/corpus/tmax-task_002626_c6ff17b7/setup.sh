#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    mkdir -p /home/user
    cat << 'EOF' > /home/user/citations.csv
1,2
2,3
1,4
4,3
3,5
6,2
7,8
8,9
7,9
EOF
rm -rf /home/user/.setup_tmp
