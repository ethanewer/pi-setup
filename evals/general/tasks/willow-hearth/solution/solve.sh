#!/bin/bash
# Oracle for willow-hearth. Produces every deliverable by doing the real work:
#   - writes the recovery program /app/decode.c
#   - uses it to recover the subkey and decrypt the ciphertext record
#   - cracks the archive password (dictionary) and pulls its secret
#   - builds the combined key+certificate PEM
#   - records recovered credentials in /app/creds.txt
set -eu
cd /app

# ---- 1) deliver the recovery program (the reference implementation) ----
cp /solution/decode.c /app/decode.c
gcc -O2 -o /tmp/decode /app/decode.c

# ---- 2) run the recovery: key + decrypted record (real work) ----
OUT=$(/tmp/decode /app/artifacts/pairs.txt /app/artifacts/target.hex)
SUBKEY=$(printf '%s\n' "$OUT" | sed -n '1s/^key=//p')
PLAINHEX=$(printf '%s\n' "$OUT" | sed -n '2s/^plain=//p')
RECORD=$(python3 -c "import sys;sys.stdout.write(bytes.fromhex(sys.argv[1]).decode('latin1'))" "$PLAINHEX")

# ---- 3) crack the encrypted archive (real dictionary search) ----
PASS=$(python3 - <<'PY'
import zipfile
for w in [l.rstrip("\n") for l in open("/app/artifacts/dict.txt")]:
    try:
        z = zipfile.ZipFile("/app/artifacts/secrets.zip")
        z.extractall("/tmp/artout", pwd=w.encode())
        z.close()
        print(w); break
    except Exception:
        continue
PY
)

# ---- 4) generate a combined key+certificate PEM ----
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/keyonly.pem -out /tmp/certonly.pem \
    -days 30 -subj "/CN=prepared-pile" -addext "subjectAltName=DNS:prepared.internal" >/dev/null 2>&1
{ cat /tmp/keyonly.pem; cat /tmp/certonly.pem; } > /app/key.pem
chmod 600 /app/key.pem
rm -f /tmp/keyonly.pem /tmp/certonly.pem

# ---- 5) record recovered credentials ----
{
    printf 'subkey=%s\n' "$SUBKEY"
    printf 'passphrase=%s\n' "$PASS"
    printf 'record=%s\n' "$RECORD"
} > /app/creds.txt

echo "oracle done: subkey=$SUBKEY record=$RECORD pass=$PASS"