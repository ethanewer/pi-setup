#!/bin/bash
set -euo pipefail
mkdir -p /app
rm -rf /app/pulled
export GIT_SSH_COMMAND="ssh -i /keys/agent_key -o HostKeyAlgorithms=+ssh-ed25519 -o StrictHostKeyChecking=no"
git clone sshgit@127.0.0.1:/home/sshgit/repos/team.git /app/pulled