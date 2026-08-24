#!/bin/bash
set -euo pipefail
mkdir -p /app
ssh -i /keys/agent_key -o StrictHostKeyChecking=no alice@127.0.0.1 \
    'cat /home/alice/secret.txt' > /app/ssh.txt