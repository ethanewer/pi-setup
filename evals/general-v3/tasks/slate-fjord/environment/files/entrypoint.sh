#!/bin/bash
# entrypoint.sh - provisions the loopback SSH password-auth git server and
# starts sshd (ports 22 and 2222) at every container start, then execs the
# harness command.
set -e

# --- dedicated git-server account with a known password (local only) -------
id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash deploy
echo 'deploy:bedrock7' | chpasswd
chown -R deploy:deploy /srv/git

# --- sshd: password auth only, loopback, ports 22 and 2222 -----------------
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config <<'CFG'
Port 22
ListenAddress 127.0.0.1
PasswordAuthentication yes
PubkeyAuthentication no
KbdInteractiveAuthentication yes
UsePAM no
PermitEmptyPasswords no
PerSourcePenalties no
PrintMotd no
CFG
sed 's/^Port 22$/Port 2222/' /etc/ssh/sshd_config > /etc/ssh/sshd_config_alt
echo 'PidFile /run/sshd-alt.pid' >> /etc/ssh/sshd_config_alt

# --- start both daemons (idempotent), then wait until both ports answer ----
/usr/sbin/sshd || true
/usr/sbin/sshd -f /etc/ssh/sshd_config_alt || true
for i in $(seq 1 50); do
  if (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null; then
    if (exec 3<>/dev/tcp/127.0.0.1/2222) 2>/dev/null; then
      break
    fi
  fi
  sleep 0.2
done

exec "$@"
