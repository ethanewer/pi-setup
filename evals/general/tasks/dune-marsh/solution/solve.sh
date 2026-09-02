#!/bin/bash
# Oracle for dune-marsh: write the enable_auth.sh deliverable, run it on the
# visible config, and capture the hash into /app/auth_hash.txt.
# Never reads /tests.
set -eu

ENABLE="/app/enable_auth.sh"
HASHFILE="/app/auth_hash.txt"
CONFIG="/app/gateway/config.json"

# ---- 1. Write the deliverable script (this IS the work, not a canned answer).
cat > "$ENABLE" <<'SH'
#!/bin/bash
# Enable password-based authentication on a LanternGate gateway config.
# Usage: enable_auth.sh [CONFIG_PATH]   (default /app/gateway/config.json)
# Prints the installed hash to stdout; logs go to stderr. Idempotent.
set -eu

SECRET='SableKey-68North'
CONFIG_PATH="${1:-/app/gateway/config.json}"

python3 - "$CONFIG_PATH" "$SECRET" <<'PY'
import hashlib, json, os, secrets, sys

config_path, secret = sys.argv[1], sys.argv[2]
with open(config_path, "r", encoding="utf-8") as fh:
    cfg = json.load(fh)
auth = cfg.get("auth")
if not isinstance(auth, dict):
    raise SystemExit("config has no auth object")
iters = auth.get("iterations")
if not isinstance(iters, int) or iters < 1:
    raise SystemExit("config auth.iterations missing or invalid")
salt = secrets.token_bytes(16)
dk = hashlib.pbkdf2_hmac("sha256", secret.encode("utf-8"), salt, iters)
auth["enabled"] = True
auth["password_hash"] = "pbkdf2_sha256$%d$%s$%s" % (
    iters, salt.hex(), dk.hex())
tmp = config_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
os.replace(tmp, config_path)
print(auth["password_hash"])
PY
SH
chmod +x "$ENABLE"

# ---- 2. Run it on the visible config and capture the installed hash.
HASH="$(bash "$ENABLE" "$CONFIG")"
printf '%s\n' "$HASH" > "$HASHFILE"

# Self-check: idempotent re-run, then the config must still verify.
bash "$ENABLE" "$CONFIG" >/dev/null
python3 - "$CONFIG" "$HASHFILE" <<'PY'
import hashlib, json, sys
SECRET = "SableKey-68North"
cfg = json.load(open(sys.argv[1]))
auth = cfg["auth"]
assert auth["enabled"] is True
h = auth["password_hash"]
parts = h.split("$")
assert len(parts) == 4 and parts[0] == "pbkdf2_sha256"
iters, salt, dk = int(parts[1]), bytes.fromhex(parts[2]), bytes.fromhex(parts[3])
assert iters == auth["iterations"]
assert hashlib.pbkdf2_hmac("sha256", SECRET.encode(), salt, iters) == dk
line = open(sys.argv[2]).read().strip()
p = line.split("$")
assert len(p) == 4
assert hashlib.pbkdf2_hmac("sha256", SECRET.encode(),
                           bytes.fromhex(p[2]), int(p[1])) == bytes.fromhex(p[3])
print("oracle self-check OK")
PY

echo "solve.sh done -> $ENABLE and $HASHFILE"
