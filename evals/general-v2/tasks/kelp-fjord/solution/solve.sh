#!/bin/bash
# Real oracle for kelp-fjord: write the sealing script, then RUN it once on the
# visible fixtures to produce /app/records.gpg and /app/cipher-choice.txt.
# Never reads /tests.
set -eu

cat > /app/seal.sh <<'SH'
#!/bin/bash
# Halcyon Diagnostics nightly export seal.
# Reads the live passphrase file, builds a deterministic plaintext snapshot
# under /tmp only, seals it with AES-256 symmetric GPG, and removes every
# plaintext intermediate.
set -eu

PASS_FILE="/app/.seal-key"
OUT="/app/records.gpg"
SNAP="/tmp/hdx-snapshot.$$.tar.gz"

# 1. snapshot /app/exports deterministically (reproducible tar metadata,
#    timestamp-free gzip header), transient plaintext under /tmp only.
tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0 --numeric-owner \
    -C /app -cf - exports | gzip -n > "$SNAP"

# 2. record the strongest symmetric cipher gpg offers (per `man gpg`).
printf 'AES256\n' > /app/cipher-choice.txt

# 3. seal with exactly AES-256 and the strongest S2K digest.
gpg --batch --yes --pinentry-mode loopback \
    --passphrase-file "$PASS_FILE" \
    --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
    --output "$OUT" "$SNAP"

# 4. remove every plaintext intermediate.
shred -u "$SNAP" 2>/dev/null || rm -f "$SNAP"

exit 0
SH

chmod +x /app/seal.sh

bash /app/seal.sh

echo "solve.sh done"
ls -l /app/seal.sh /app/records.gpg /app/cipher-choice.txt
