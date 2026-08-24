#!/bin/bash
# Starts a real OpenSSH sshd server in the container at boot and keeps the shell alive.
set -e
mkdir -p /run/sshd /home/alice
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key
fi
/usr/sbin/sshd
sleep 2147483647