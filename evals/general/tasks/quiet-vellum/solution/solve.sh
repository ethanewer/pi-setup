#!/bin/bash
# Oracle for quiet-vellum: author the reusable shell provisioner, run it for
# the visible case (nightlog -> /bin/dash), and emit the account report from
# the real user-database lookup. Never reads /tests.
set -eu

PROVISION="/app/provision.sh"
REPORT="/app/shell_report.json"

# ---- 1. Write the deliverable provisioner (this IS the work).
cat > "$PROVISION" <<'SH'
#!/bin/bash
# Set the default login shell of an existing local user, persistently.
# Usage: provision.sh <username> <shell>
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <username> <shell>" >&2
    exit 2
fi

user="$1"
shell="$2"

# The account must exist in the local user database.
if ! getent passwd "$user" >/dev/null 2>&1; then
    echo "no such user: $user" >&2
    exit 3
fi

# The shell binary must exist so the account stays usable.
if [ ! -x "$shell" ]; then
    echo "shell not executable: $shell" >&2
    exit 4
fi

# Persist the default login shell in the account database (idempotent).
usermod -s "$shell" "$user"

# Confirm the user-database lookup now reports the requested shell.
current="$(getent passwd "$user" | cut -d: -f7)"
if [ "$current" != "$shell" ]; then
    echo "lookup still reports $current for $user" >&2
    exit 5
fi
SH
chmod +x "$PROVISION"

# ---- 2. Visible case: actually change the default shell, persistently.
bash "$PROVISION" nightlog /bin/dash
# Idempotency: a second run must succeed and change nothing.
bash "$PROVISION" nightlog /bin/dash

# ---- 3. Report the real account-database state.
actual="$(getent passwd nightlog | cut -d: -f7)"
printf '{\n  "user": "nightlog",\n  "default_shell": "%s"\n}\n' "$actual" > "$REPORT"

echo "solve.sh done -> $PROVISION and $REPORT"
cat "$REPORT"
