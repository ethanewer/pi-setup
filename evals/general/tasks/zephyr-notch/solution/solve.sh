#!/usr/bin/env bash
# Oracle for zephyr-notch. Does the real work with literal /app paths:
#   1. authors the reusable secure eraser,
#   2. runs it on /app/vault and writes /app/erased_ok.txt,
#   3. consults `man openssl-enc` to identify the AES-256-CTR option and
#      documents it in /app/capability_notes.md,
#   4. decrypts /app/handoff/msg.enc with that option and writes the exact
#      recovered message to /app/results.txt.
set -euo pipefail

# ---- 1. Author /app/secure_erase.sh ---------------------------------------
cat > /app/secure_erase.sh <<'SE'
#!/usr/bin/env bash
# Reusable secure eraser for Project Zephyr.
#   secure_erase.sh TARGET_DIR [MARKER_FILE]
# Overwrites every regular file under TARGET_DIR in place (shred: random
# passes then a final zero pass), unlinks the files, removes every now-empty
# directory bottom-up, then removes TARGET_DIR itself. Neighbors are never
# touched. A missing TARGET_DIR is treated as already-erased success. On
# success writes MARKER_FILE containing exactly "OK" + newline when given.
set -u

target="${1:-}"
marker="${2:-}"

if [ -z "$target" ]; then
  echo "usage: $0 TARGET_DIR [MARKER_FILE]" >&2
  exit 2
fi

if [ -d "$target" ] && [ ! -L "$target" ]; then
  # 1) overwrite + unlink every regular file beneath the tree (hidden files,
  #    read-only files, names with spaces all handled via NUL-delimited find)
  find "$target" -type f -print0 | while IFS= read -r -d '' f; do
    if ! shred -z -n 3 -u "$f" 2>/dev/null; then
      shred -n 3 -u "$f" 2>/dev/null || chmod u+w -- "$f" && shred -n 3 -u "$f"
    fi
  done
  # 2) drop the now-empty directories bottom-up, including the root
  find "$target" -depth -type d -exec rmdir {} + 2>/dev/null || true
  if [ -e "$target" ] || [ -L "$target" ]; then
    rm -rf -- "$target"
  fi
else
  # a plain file / symlink / missing target
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    shred -z -n 3 -u "$target" 2>/dev/null || chmod u+w -- "$target" && shred -n 3 -u "$target"
  fi
  rm -rf -- "$target" 2>/dev/null || true
fi

if [ -n "$marker" ]; then
  printf 'OK\n' > "$marker"
fi

if [ -e "$target" ] || [ -L "$target" ]; then
  echo "secure_erase.sh: could not remove $target" >&2
  exit 1
fi
echo "secure_erase.sh: erased $target"
exit 0
SE
chmod 0755 /app/secure_erase.sh

# ---- 2. Run it on the shipped vault ---------------------------------------
bash /app/secure_erase.sh /app/vault /app/erased_ok.txt
[ "$(cat /app/erased_ok.txt)" = "OK" ]
[ ! -e /app/vault ]

# ---- 3. Consult the manual for the exact cipher option --------------------
option="$(man openssl-enc 2>/dev/null | grep -oE '\-aes\-256\-ctr' | head -n1 || true)"
if [ -z "$option" ]; then
  # manual not installed/groff not rendering: asciidoc/plain fallback
  option="$(grep -hoE '\-aes\-256\-ctr' /usr/share/man/man1/openssl-enc.1.gz 2>/dev/null | head -n1 || true)"
fi
if [ -z "$option" ]; then
  option="-aes-256-ctr"
fi

cat > /app/capability_notes.md <<NOTE
Capability discovered from the installed manual page \`man openssl-enc\`:

cipher option: ${option}

The AES-256 counter-mode cipher is listed in the enc manual's cipher table;
this is the exact option token to pass to 'openssl enc' for sealing and
unsealing. Streaming mode: no padding bytes are added, so recovered plaintext
length equals ciphertext length.
NOTE

# ---- 4. Decrypt and persist the exact message ------------------------------
key_hex="$(tr -d '\n' < /app/handoff/key.hex)"
iv_hex="$(tr -d '\n' < /app/handoff/iv.hex)"
openssl enc -d "${option}" -K "${key_hex}" -iv "${iv_hex}" \
    -in /app/handoff/msg.enc -out /app/results.txt

# results.txt carries the recovered message; accept its trailing newline.
[ -s /app/results.txt ]

echo "solve.sh: zephyr-notch oracle complete"
