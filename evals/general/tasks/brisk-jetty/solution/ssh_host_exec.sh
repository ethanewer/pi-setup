#!/bin/bash
# ssh_host_exec.sh — run an arbitrary remote command inside the running Nysa relay
# guest over the forwarded host port 127.0.0.1:61234 (which qemu user-mode
# networking forwards into the guest's sshd on 22).
#
# Usage:
#   bash /app/ssh_host_exec.sh "<remote command>..."   run it in the guest
#   bash /app/ssh_host_exec.sh                          -> usage + nonzero exit
#
# Prints the remote command's stdout; exits with ssh's status.
set -u

PORT="${NYSA_SSH_PORT:-61234}"
PASSWORD="${NYSA_ROOT_PASSWORD:-kestrel-mistral-1987}"

if [ $# -eq 0 ]; then
  echo "usage: $0 <remote command...>" >&2
  exit 2
fi

export SSHPASS="$PASSWORD"
exec sshpass -e ssh -p "$PORT" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=6 \
  -o NumberOfPasswordPrompts=1 \
  root@127.0.0.1 "$@"
