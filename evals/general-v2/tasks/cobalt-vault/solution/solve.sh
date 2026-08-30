#!/bin/bash
# Real oracle for cobalt-vault: install the recovery tool, run it on the
# visible artifacts to produce /app/seed.txt and /app/message.txt.
# Never reads /tests.
set -eu

TOOL="/app/attack.py"
cp "$(cd "$(dirname "$0")" && pwd)/attack.py" "$TOOL"
chmod +x "$TOOL"

OUT="$(mktemp -d)"
python3 "$TOOL" /app/vault/pairs.txt /app/vault/target.hex > "$OUT/run.txt"
cat "$OUT/run.txt"

SEED_LINE="$(sed -n 's/^seed=//p' "$OUT/run.txt")"
PLAIN_HEX="$(sed -n 's/^plain=//p' "$OUT/run.txt")"
[ -n "$SEED_LINE" ] && [ -n "$PLAIN_HEX" ]

printf 'seed=%s\n' "$SEED_LINE" > /app/seed.txt
python3 - "$PLAIN_HEX" > /app/message.txt <<'PY'
import sys
h = sys.argv[1].strip()
sys.stdout.write(bytes.fromhex(h).decode("latin1"))
PY

echo "solve.sh done -> $TOOL /app/seed.txt /app/message.txt"
ls -l "$TOOL" /app/seed.txt /app/message.txt
