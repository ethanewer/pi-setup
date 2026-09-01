#!/bin/bash
# Oracle for mist-quay: write both provisioning scripts, make them
# executable, then RUN /app/configure.sh to activate the deployed state.
# Never reads /tests.
set -eu

ADDUSER="/app/adduser.sh"
CONFIGURE="/app/configure.sh"

# ---- 1. /app/adduser.sh: general SHA-512-crypt credential updater.
cat > "$ADDUSER" <<'SH'
#!/bin/bash
set -eu
if [ "$#" -ne 2 ]; then
    echo "usage: adduser.sh <user> <password>" >&2
    exit 2
fi
USER_NAME="$1"
PASSWORD="$2"
HT=/app/service/users.htpasswd
touch "$HT"
TMP="$(mktemp)"
grep -v "^${USER_NAME}:" "$HT" > "$TMP" || true
mv "$TMP" "$HT"
HASH="$(python3 -c 'import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))' "$PASSWORD")"
printf '%s:%s\n' "$USER_NAME" "$HASH" >> "$HT"
chmod 644 "$HT"
SH

# ---- 2. /app/configure.sh: enable auth, register the operator account.
cat > "$CONFIGURE" <<'SH'
#!/bin/bash
set -eu
CFG=/app/service/config.ini
sed -i 's/^enabled[[:space:]]*=.*/enabled = true/' "$CFG"
/app/adduser.sh marlow 'MistQuay#Runnel-52'
SH

chmod +x "$ADDUSER" "$CONFIGURE"

# ---- 3. Activate the deployed state.
"$CONFIGURE"

echo "solve.sh done -> $ADDUSER and $CONFIGURE (configured)"
ls -l "$ADDUSER" "$CONFIGURE" /app/service/users.htpasswd
