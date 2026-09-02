#!/bin/bash
# entrypoint.sh - provisions the local SSH password-auth remote user and starts
# the SSH daemon at every container start, then runs the harness command.
set -e

# --- dedicated remote user with a known password (local only) --------------
id gitdev >/dev/null 2>&1 || useradd -m -s /bin/bash gitdev
echo 'gitdev:eastbank4' | chpasswd
chown -R gitdev:gitdev /srv/git

# --- sshd: allow password auth over loopback -------------------------------
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config <<'CFG'
Port 22
ListenAddress 127.0.0.1
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM no
PermitEmptyPasswords no
PrintMotd no
CFG

# --- ensure the daemon is up before we exec the harness command ------------
if ! pgrep -x sshd >/dev/null 2>&1; then
  /usr/sbin/sshd
  for i in $(seq 1 20); do
    pgrep -x sshd >/dev/null 2>&1 && break
    sleep 0.2
  done
fi

exec "$@"
