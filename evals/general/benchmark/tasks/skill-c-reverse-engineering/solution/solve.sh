#!/usr/bin/env bash
set -euo pipefail

# Known constants: KEY = 0x2A, password encoded table from the binary.
# Decode the password the same way the intended reverse-engineering path does.
python3 - <<'PY_END'
key = 0x2A
enc = [0x58, 0x19, 0x5c, 0x19, 0x58, 0x59, 0x19, 0x75, 0x47, 0x19]
print("".join(chr(b ^ key) for b in enc))
PY_END

PASSWORD=$(python3 - <<'PY_END'
key = 0x2A
enc = [0x58, 0x19, 0x5c, 0x19, 0x58, 0x59, 0x19, 0x75, 0x47, 0x19]
print("".join(chr(b ^ key) for b in enc))
PY_END
)

FLAG=$(/app/chal "$PASSWORD")
echo "$FLAG" | grep -q '^FLAG{'
printf '%s\n' "$FLAG" > /app/flag.txt