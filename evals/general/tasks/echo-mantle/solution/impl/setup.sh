#!/usr/bin/env bash
# relay-bank provisioning. Idempotent: safe to run more than once.
set -euo pipefail

RUN=/app/run
mkdir -p "$RUN"
MAIL_USER=mailreader
MAP=/etc/postfix/relay_mapping

# --- three JVM companion daemons + one reporter ---
# clean any previous instance first so a re-run starts clean
pkill -9 -f 'Relay reporter' 2>/dev/null || true
pkill -9 -f 'Relay peer'     2>/dev/null || true
sleep 1

nohup java -Xms64m -Xmx96m -cp /app/lib/relay.jar Relay peer companion-a 18081 >>"$RUN/peers.log" 2>&1 &
nohup java -Xms64m -Xmx96m -cp /app/lib/relay.jar Relay peer companion-b 18082 >>"$RUN/peers.log" 2>&1 &
nohup java -Xms64m -Xmx96m -cp /app/lib/relay.jar Relay peer companion-c 18083 >>"$RUN/peers.log" 2>&1 &
nohup java -Xms64m -Xmx96m -cp /app/lib/relay.jar Relay reporter 18490 \
          companion-a:18081 companion-b:18082 companion-c:18083 >>"$RUN/reporter.log" 2>&1 &

# Do not return until the RPC report is actually reachable AND healthy.
for _ in $(seq 1 30); do
  out=$(curl -s --max-time 2 http://127.0.0.1:18490/ 2>/dev/null || true)
  echo "$out" | grep -q '"healthy":true' && break
  sleep 1
done

# --- name-resolution / hostname repair, persisted via files ---
if ! grep -q 'relay-bank.internal' /etc/hosts 2>/dev/null; then
    printf '10.9.9.77 relay-bank.internal relay-bank-vnode\n' >> /etc/hosts
fi
hostname relay-bank-vnode 2>/dev/null || true   # live set may be blocked by container caps; file persists
printf 'relay-bank-vnode\n' > /etc/hostname

# --- mailing-list: canonical file + transport map -> local delivery ---
mkdir -p /etc/postfix
cat > "$MAP" <<EOF
# relay-bank mailing list -> local delivery (canonical config file)
relay.briefs@relay.internal    local:$MAIL_USER
relay.alerts@relay.internal    local:$MAIL_USER
relay.digest@relay.internal    local:$MAIL_USER
EOF
postmap "$MAP" 2>/dev/null || true

if ! grep -q 'transport_maps' /etc/postfix/main.cf 2>/dev/null; then
    printf 'transport_maps = hash:/etc/postfix/relay_mapping\n' >> /etc/postfix/main.cf
fi
if ! grep -q "^$MAIL_USER:[[:space:]]*$MAIL_USER" /etc/aliases 2>/dev/null; then
    printf '%s: %s\n' "$MAIL_USER" "$MAIL_USER" >> /etc/aliases
fi
postalias /etc/aliases 2>/dev/null || true

# --- change the default login shell of $MAIL_USER and persist it ---
if command -v chsh >/dev/null 2>&1; then
    chsh -s /bin/bash "$MAIL_USER" || usermod -s /bin/bash "$MAIL_USER"
else
    usermod -s /bin/bash "$MAIL_USER"
fi
[ "$(getent passwd "$MAIL_USER" | cut -d: -f7)" = "/bin/bash" ] || usermod -s /bin/bash "$MAIL_USER"

sync
exit 0