#!/bin/bash
# Real oracle for sorrel-hasp: write the reusable keygen.sh deliverable, then
# RUN it to produce the 2048-bit /app/deploy_key.pem with mode 0600. Never
# reads /tests.
set -eu

KEYGEN="/app/keygen.sh"
DEPLOY="/app/deploy_key.pem"

cat > "$KEYGEN" <<'EOF'
#!/usr/bin/env bash
# keygen.sh <bits> <output_path>
# Generate an unencrypted RSA private key of <bits> bits in PEM form at
# <output_path>, with file mode 0600 regardless of umask.
# Policy: bits must be a decimal integer in [2048, 8192]; violations exit 2
# and leave the filesystem untouched.
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: keygen.sh <bits> <output_path>" >&2
    exit 2
fi

bits="$1"
out="$2"

# bits must be a pure decimal integer (reject empty, signs, other chars)
case "$bits" in
    ''|*[!0-9]*)
        echo "keygen.sh: bits must be a decimal integer, got '$bits'" >&2
        exit 2
        ;;
esac

# guard against absurd lengths before arithmetic comparison
if [ "${#bits}" -gt 4 ]; then
    echo "keygen.sh: bits out of allowed range [2048, 8192], got '$bits'" >&2
    exit 2
fi

if [ "$bits" -lt 2048 ] || [ "$bits" -gt 8192 ]; then
    echo "keygen.sh: bits out of allowed range [2048, 8192], got '$bits'" >&2
    exit 2
fi

# Generate unencrypted PKCS#8 RSA key. Do not rely on umask for the mode:
# write, then set the mode explicitly before and after moving into place.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
openssl genpkey -algorithm RSA \
    -pkeyopt "rsa_keygen_bits:$bits" -out "$tmp" 2>/dev/null
chmod 600 "$tmp"
mv -f "$tmp" "$out"
chmod 600 "$out"
EOF
chmod 755 "$KEYGEN"

# Produce the visible deliverable by actually running the generator.
"$KEYGEN" 2048 "$DEPLOY"

echo "solve.sh done -> $KEYGEN and $DEPLOY"
ls -l "$KEYGEN" "$DEPLOY"
openssl pkey -in "$DEPLOY" -noout -text | head -n 1
stat -c '%a %n' "$DEPLOY"
