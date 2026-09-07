#!/bin/bash
# Oracle for cobalt-quill: install the recovery program, compile it, run it on
# the visible artifacts to recover the key and payload, and write /app/creds.txt
# from the real recovered values. Never reads /tests.
set -euo pipefail

# Install the recovery program from the task's own source rather than embedding a
# second copy here. This oracle used to carry the whole of keyfind.c inside a
# heredoc, so there were two copies of the same C file in the task, and fixing one
# left the other in place: the tokenizer bug that made recover_key return 0 for
# every fixture was repaired in solution/keyfind.c while the embedded copy -- the
# one that actually compiles and runs -- kept discarding every pair. One source of
# truth, mounted at /solution the same way the other oracles in this suite take
# their deliverables.
install -m 0644 /solution/keyfind.c /app/keyfind.c

gcc -O2 -o /tmp/oracle_keyfind /app/keyfind.c

OUT=$(/tmp/oracle_keyfind /app/artifacts/pairs.txt /app/artifacts/target.hex)
KEY=$(printf '%s\n' "$OUT" | sed -n 's/^key=//p')
PLAIN=$(printf '%s\n' "$OUT" | sed -n 's/^plain=//p')

# decode the payload to ASCII (8 hex digits = 4 bytes big-endian), then trim
# trailing pad spaces, and write the credentials file from the real values.
RECORD=$(python3 -c '
import sys
hx = sys.argv[1]
b = bytes.fromhex(hx)
s = b.decode("ascii", errors="replace")
print(s.rstrip(" "))
' "$PLAIN")

printf 'subkey=%s\nrecord=%s\n' "$KEY" "$RECORD" > /app/creds.txt
cat /app/creds.txt
