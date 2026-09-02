#!/bin/bash
# Real oracle for quiet-keel: write the reusable set_shell.sh deliverable,
# apply the runbook entry from /app/requirement.txt, and record the outcome
# in /app/answer.txt. Never reads /tests.
set -eu

SCRIPT="/app/set_shell.sh"
ANSWER="/app/answer.txt"
REQ="/app/requirement.txt"

# ---- 1. Write the deliverable script (this IS the work, not a canned answer).
cat > "$SCRIPT" <<'SH'
#!/bin/bash
# set_shell.sh <username> <new_shell> — permanently change a user's default
# login shell. Validates user and shell, touches nothing else, idempotent.
set -u

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <username> <new_shell>" >&2
    exit 2
fi

user="$1"
new_shell="$2"

# Validate: target shell must be an existing, executable file.
if [ ! -x "$new_shell" ]; then
    echo "error: shell '$new_shell' is not an existing executable file" >&2
    exit 1
fi

# Validate: user must exist in the account database.
if ! getent passwd "$user" >/dev/null 2>&1; then
    echo "error: user '$user' does not exist" >&2
    exit 1
fi

# Persistently update the login-shell field (user database, not transient).
if command -v usermod >/dev/null 2>&1; then
    usermod -s "$new_shell" "$user"
else
    # Fallback: careful /etc/passwd edit, preserving every other field.
    tmp="$(mktemp)"
    awk -F: -v u="$user" -v s="$new_shell" \
        'BEGIN{OFS=FS} $1==u{$7=s} {print}' /etc/passwd > "$tmp"
    cat "$tmp" > /etc/passwd
    rm -f "$tmp"
fi

# Confirm the account lookup now reports the new shell.
got="$(getent passwd "$user" | cut -d: -f7)"
if [ "$got" != "$new_shell" ]; then
    echo "error: shell not applied (lookup reports '$got')" >&2
    exit 1
fi

exit 0
SH
chmod +x "$SCRIPT"

# ---- 2. Apply the runbook entry (guarded parse of requirement.txt).
req_user="$(sed -n 's/^user=//p' "$REQ" | head -n 1)"
req_shell="$(sed -n 's/^shell=//p' "$REQ" | head -n 1)"
if [ -z "$req_user" ] || [ -z "$req_shell" ]; then
    echo "error: could not parse $REQ" >&2
    exit 1
fi

"$SCRIPT" "$req_user" "$req_shell"

# ---- 3. Record the outcome.
printf '%s:%s\n' "$req_user" "$req_shell" > "$ANSWER"

echo "solve.sh done -> $SCRIPT and $ANSWER"
ls -l "$SCRIPT" "$ANSWER"
getent passwd "$req_user"
