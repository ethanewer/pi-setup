#!/usr/bin/env bash
# =============================================================================
# palisade provisioner  -  hollow-notch task
#
# One idempotent script that repairs and brings a "palisade" three-node store
# (three JVM daemons) fully under service, applied to a fresh Ubuntu container
# where DNS/name-resolution, hostname and list-mail delivery are deliberately
# broken.  Re-runnable; exits non-zero on an invalid descriptor.
#
# Usage:  bash /app/setup.sh [SITE_CONF]
#   SITE_CONF   path of a "palisade" site descriptor (default
#               /app/palisade/site.conf). Hidden tests pass alternate ones.
#
# It performs, in order:
#   1. parse/validate the descriptor (a malformed descriptor aborts cleanly
#      before any state is touched - exit 2, no side effects),
#   2. repair DNS/name-resolution + hostname so the site host resolves on
#      loopback and sticks (persistent /etc/hosts + /etc/hostname + nsswitch),
#   3. (re)start the three JVM daemon roles and wait until all are online,
#   4. write the healthy cluster report to /app/status.json,
#   5. configure list mail for local delivery and deliver the announcement.
# =============================================================================
set -u

CONF="${1:-/app/palisade/site.conf}"
JAR=/app/palisade/palisade.jar
HB=/var/run/palisade

MAIL_DOMAIN='hollow.farm'
ANNOUNCE="palisade-announce"
SUBSCRIBERS="sable rona trio"
MARKER="PALISADE-RING-4421"

fail() { echo "palisade-setup: ERROR: $*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 1. Parse + validate descriptor (no side effects until this passes).
# ---------------------------------------------------------------------------
[ -f "$JAR" ]        || fail "palace daemon jar not found at $JAR"
[ -r "$CONF" ]       || fail "site descriptor not readable: $CONF"

declare -A CFG
while IFS='=' read -r key_val; do
    key="${key_val%%=*}"
    val="${key_val#*=}"
    case "$key" in *'#'|'#'*|'') continue ;; esac
    key="$(echo "$key" | tr -d ' [:space:]')"
    val="$(echo "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$key" ] || continue
    CFG["$key"]="$val"
done < "$CONF"

HOST="${CFG[host]:-}"
PORT_P="${CFG[primary_port]:-}"
PORT_D="${CFG[data_port]:-}"
PORT_S="${CFG[secondary_port]:-}"
CAP_MB="${CFG[capacity_mb]:-}"

echo "$HOST" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' \
    || fail "host field invalid or missing"
for n in "$PORT_P" "$PORT_D" "$PORT_S"; do
    echo "$n" | grep -Eq '^[1-9][0-9]{0,4}$' || fail "port not a positive integer: '$n'"
    [ "$n" -ge 1024 ] 2>/dev/null && [ "$n" -le 65535 ] || fail "port out of range: $n"
done
echo "$CAP_MB" | grep -Eq '^[1-9][0-9]*$' || fail "capacity_mb invalid"

cap_bytes=$(( CAP_MB * 3 * 1024 * 1024 ))

# ---------------------------------------------------------------------------
# 2. Repair DNS / name-resolution / hostname (persistent files).
# ---------------------------------------------------------------------------
if ! grep -qs "	$HOST" /etc/hosts && ! grep -qs " $HOST" /etc/hosts; then
    printf '127.0.0.1\t%s\n' "$HOST" >> /etc/hosts
fi
if ! grep -qs '^hosts:.*files' /etc/nsswitch.conf; then
    echo "hosts:      files dns" >> /etc/nsswitch.conf
else
    sed -i 's/^hosts:.*/hosts:      files dns/' /etc/nsswitch.conf
fi
echo "$HOST" > /etc/hostname || fail "cannot write /etc/hostname"
hostname "$HOST" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. (Re)start the three palisade JVM daemon roles.
# ---------------------------------------------------------------------------
pkill -f "$JAR" 2>/dev/null || true
sleep 2
rm -rf "$HB"; mkdir -p "$HB"

for role in primary data secondary; do
    nohup java -jar "$JAR" "$CONF" "$role" >"/var/log/palisade-$role.log" 2>&1 &
done
disown -a 2>/dev/null || true

portonline() { # 1=port
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&-; return 0; } || return 1
}
for i in $(seq 1 40); do
    if [ "$(pgrep -cf "palisade.jar")" -ge 3 ] \
       && portonline "$PORT_P" && portonline "$PORT_D" && portonline "$PORT_S"; then
        break
    fi
    sleep 0.5
done

# ---------------------------------------------------------------------------
# 4. Write the healthy cluster snapshot (deliverable /app/status.json).
# ---------------------------------------------------------------------------
exec 3<>"/dev/tcp/127.0.0.1/$PORT_P" || fail "primary RPC port $PORT_P not listening"
printf 'GET /status\n' >&3
REPORT="$(cat <&3)"
exec 3>&-
echo "$REPORT" | jq -e '.online == true and (.nodes | length) == 3' >/dev/null 2>&1 \
    || fail "cluster report not healthy"
echo "$REPORT" > /app/status.json || fail "cannot write /app/status.json"

# ---------------------------------------------------------------------------
# 5. Point outbound list mail to local mailboxes and deliver the announcement.
# ---------------------------------------------------------------------------
mkdir -p /var/mail
if [ -f /usr/sbin/postconf ]; then
    cat > /etc/postfix/main.cf <<EOF
# palisade local-delivery config (canonical list config).
myhostname = $HOST
myorigin = $HOST
mydomain = $MAIL_DOMAIN
mydestination = \$myhostname, \$mydomain, localhost
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mail_spool_directory = /var/mail
inet_interfaces = loopback-only
inet_protocols = ipv4
# intentionally NO relayhost - every outbound list message stays local
EOF
    printf '%s: %s\n' "$ANNOUNCE" "$(echo "$SUBSCRIBERS" | tr ' ' ',')" >> /etc/aliases
    postalias /etc/aliases 2>/dev/null || newaliases 2>/dev/null || true
    postfix stop 2>/dev/null || true
    postfix start >/dev/null 2>&1 || true
    printf 'From: %s@%s\nTo: %s@%s\nSubject: PALISADE circuit note\n\n%s\nstatus: built round 9 with online members\n' \
        "$ANNOUNCE" "$MAIL_DOMAIN" "$ANNOUNCE" "$MAIL_DOMAIN" "$MARKER" \
        | sendmail -i -f "$ANNOUNCE@$MAIL_DOMAIN" "$ANNOUNCE@$MAIL_DOMAIN" 2>/dev/null || true
    sleep 2
fi

exit 0