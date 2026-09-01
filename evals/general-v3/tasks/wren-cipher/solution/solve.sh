#!/bin/bash
# Oracle for wren-cipher: author /app/seal.sh, then RUN it on the visible
# fixtures to produce /app/evidence.gpg and /app/cipher.txt. Never reads /tests.
set -eu

cat > /app/seal.sh <<'SH'
#!/bin/bash
# Seal a source directory as a symmetric AES-256 GPG archive and leave no
# plaintext intermediates behind.
set -eu

SRC="${1:-/app/evidence}"
OUT="${2:-/app/evidence.gpg}"
PASS="${3:-/app/.seal-key}"

[ -d "$SRC" ] || { echo "seal.sh: source dir '$SRC' not found" >&2; exit 1; }
[ -f "$PASS" ] || { echo "seal.sh: passphrase file '$PASS' not found" >&2; exit 1; }

WORK="$(mktemp -d /tmp/seal-XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1. transient plaintext tarball, only under /tmp
tar -C "$(dirname "$SRC")" -cf "$WORK/snapshot.tar" "$(basename "$SRC")"
gzip -n -f "$WORK/snapshot.tar"

# 2. symmetric AES-256 seal with the strongest key stretching
gpg --batch --yes --pinentry-mode loopback \
    --passphrase-file "$PASS" \
    --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
    -o "$OUT" "$WORK/snapshot.tar.gz"

# 3. no plaintext intermediates survive (workdir is removed by the trap;
#    belt-and-braces sweep of our own transient names)
rm -f "$WORK/snapshot.tar" "$WORK/snapshot.tar.gz"
echo "SEALED $OUT"
SH
chmod +x /app/seal.sh

printf 'AES256\n' > /app/cipher.txt

bash /app/seal.sh
echo "solve.sh done"
ls -l /app/seal.sh /app/evidence.gpg /app/cipher.txt
