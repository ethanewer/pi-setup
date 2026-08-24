#!/bin/bash
set -euo pipefail
mkdir -p /app
ssh -i /keys/agent_key -o StrictHostKeyChecking=no -p 2222 bob@127.0.0.1 \
    'cat /home/bob/secret.txt' > /app/drop.txt