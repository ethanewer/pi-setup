#!/bin/bash
# Real oracle for sable-hook: reverse the gatekeeper binary to recover the
# passphrase, run it to derive the deploy secret, write the deliverables and
# RUN the target application so the side-effect file is produced by a real
# app run. Never reads /tests.
set -eu

PW_FILE="/app/recovered_passphrase.txt"
RUNNER="/app/unseal.py"
OUT_DIR="/app/vault_out"
OUT_FILE="$OUT_DIR/unsealed.txt"

# ---- 1. Recover the passphrase (XOR tables in .rodata) and derive secret ----
# Static solution of the RE step: ENC[i] ^ KEY[i%4] over the two tables in
# the binary's .rodata (verifiable with: objdump -s -j .rodata /app/gatekeeper).
PASSPHRASE="tungsten-fjord"
DEPLOY_SECRET="vault-open-5e21c9a7d4"

printf '%s\n' "$PASSPHRASE" > "$PW_FILE"

# ---- 2. Write the runner that executes the target app with the secret ------
cat > "$RUNNER" <<'PY'
#!/usr/bin/env python3
"""Run the target application with the derived deploy secret so its body
executes and emits /app/vault_out/unsealed.txt."""
import sys

sys.path.insert(0, "/app")
import vault_service

SECRET = "vault-open-5e21c9a7d4"

if __name__ == "__main__":
    ok = vault_service.open_vault(SECRET)
    sys.exit(0 if ok else 1)
PY
chmod +x "$RUNNER"

# ---- 3. Actually RUN the application to produce the side-effect file -------
rm -rf "$OUT_DIR"
cd /app
python3 "$RUNNER"
test -f "$OUT_FILE"

# Sanity: the gatekeeper really validates the recovered passphrase.
out="$(/app/gatekeeper "$PASSPHRASE")"
case "$out" in
  GRANTED\ DEPLOY_SECRET=*) : ;;
  *) echo "oracle sanity check failed: $out" >&2; exit 1 ;;
esac

echo "solve.sh done -> $PW_FILE, $RUNNER, $OUT_FILE"
ls -l "$PW_FILE" "$RUNNER" "$OUT_FILE"
