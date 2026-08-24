#!/bin/bash
# Starts a DropBear SSH server on port 2222 at container boot and keeps the shell alive.
set -e
mkdir -p /run/dropbear
/usr/sbin/dropbear -p 2222 -r /etc/dropbear/dropbear_rsa_key
sleep 2147483647