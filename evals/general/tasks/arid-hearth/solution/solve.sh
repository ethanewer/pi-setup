#!/usr/bin/env bash
set -euo pipefail
cd /app

# 1) Adopt the open-but-confirm policy in the list configuration.
cat > /app/list/list.conf <<'EOF'
# arid-hearth list configuration
# policy: closed | open-auto | open-confirm
policy = open-confirm
EOF

# 2) Author the automation wrapper around the kernel.
cat > /app/list_ops.sh <<'EOF'
#!/usr/bin/env bash
set -u
KERNEL="python3 /app/list/store.py"
LOG="/app/subscribe.log"

action="${1:-}"
addr="${2:-}"

case "$action" in
  subscribe)
    out=$($KERNEL subscribe "$addr")
    rc=$?
    if [ "$rc" -eq 0 ]; then
      tok=$(printf '%s\n' "$out" | awk '/^token /{print $2}')
      printf 'event=pending address=%s status=pending policy=open-confirm token=%s\n' \
        "$addr" "$tok" >> "$LOG" 2>/dev/null || true
      printf '%s\n' "$out"
    fi
    exit "$rc"
    ;;
  confirm)
    token="${3:-}"
    $KERNEL confirm "$addr" "$token"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf 'event=confirm address=%s status=confirmed policy=open-confirm\n' \
        "$addr" >> "$LOG" 2>/dev/null || true
    fi
    exit "$rc"
    ;;
  unsubscribe|leave)
    $KERNEL unsubscribe "$addr"
    ;;
  membership|members)
    $KERNEL membership
    ;;
  *)
    echo "usage: list_ops.sh subscribe|confirm|unsubscribe|membership ADDR [TOKEN]" >&2
    exit 9
    ;;
esac
EOF
chmod +x /app/list_ops.sh

# 3) Prove a real round-trip under the policy and produce the log.
python3 /app/list/store.py reset
rm -f /app/subscribe.log
TOKEN=$(/app/list_ops.sh subscribe admin@example.test | awk '/^token /{print $2}')
[ -n "$TOKEN" ]
/app/list_ops.sh confirm admin@example.test "$TOKEN"

test -f /app/list_ops.sh
test -x /app/list_ops.sh
test -f /app/subscribe.log
grep -q 'status=pending' /app/subscribe.log
grep -q 'status=confirmed' /app/subscribe.log
echo "solve done"