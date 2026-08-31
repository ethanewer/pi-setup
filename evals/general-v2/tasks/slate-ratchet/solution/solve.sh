#!/bin/bash
# Oracle for slate-ratchet: recover the activation codes by reimplementing the
# recorded validation logic from /app/src/vault.c, then (belt and braces)
# confirm each code against the shipped reference checker.
set -eu

CODES="/app/codes.txt"

python3 - <<'PY'
ALPH = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
M32 = 0xFFFFFFFF
MASK = 0x5A5A5A5A

# Profiles exactly as recorded in /app/src/vault.c (constants still
# obfuscated here; unmasked the same way unmask() does).
TABLE = [
    ("A", 1, 0x00002F1A, 0x1B9C1437, 0x5A5A3A43, 0x5A5A598B, 0x2A6E9BC0, 0x5A5A599F),
    ("B", 1, 0x0001B7C3, 0x5B00146F, 0x5A5A792F, 0x5A5A598B, 0x44800DBC, 0x5A5A58A7),
    ("C", 1, 0x0000C0DE, 0x5A5B5797, 0x5A5A2033, 0x5A5A598B, 0x0AA26DFD, 0x5A5A5978),
    ("D", 0, 0x00005EED, 0x5A5919A7, 0x5A7CC499, 0x5A5A598B, 0x50278444, 0x5A5A5B0C),
]

def roll(h, s):
    for c in s:
        h = (h * 31 + ord(c)) & M32
    return h

lines = []
for pid, enabled, seed, oa, ob, oc, ohash, ochk in TABLE:
    if not enabled:
        continue
    A, B = oa ^ MASK, ob ^ MASK
    state = seed
    chars = []
    for i in range(16):
        state = (state * A + B + 0x9E3779B9 * i) & 0x7FFFFFFF
        chars.append(ALPH[(state >> 13) & 31])
    code = "".join(chars)
    # cross-check both redundant gates recorded in the source
    vsum = sum(ALPH.index(c) for c in code)
    assert roll(5381, code) == ohash ^ MASK, pid
    assert (vsum * (oc ^ MASK)) % 997 == ochk ^ MASK, pid
    lines.append("%s=%s" % (pid, code))

with open("/app/codes.txt", "w") as fh:
    fh.write("\n".join(lines) + "\n")
print("recovered codes for:", ", ".join(l.split("=")[0] for l in lines))
PY

# Confirm every recovered code is accepted by the pristine reference checker.
while IFS= read -r line; do
    case "$line" in
        ''|'#'*) continue ;;
    esac
    prof="${line%%=*}"
    code="${line#*=}"
    out="$(/app/src/vault "$prof" "$code")"
    case "$out" in
        ACCEPT*) ;;
        *) echo "reference checker rejected $prof" >&2; exit 1 ;;
    esac
done < "$CODES"

echo "solve.sh done -> $CODES"
cat "$CODES"
