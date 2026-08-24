#!/bin/bash
# Oracle solution for item-076-main: install a working decoder at /app/solve/decode.py.
set -e
mkdir -p /app/solve
cat > /app/solve/decode.py <<'PY'
import sys

def decode(data):
    # Header: 2-byte little-endian total output length.
    n = data[0] | (data[1] << 8)
    out = bytearray()
    p = 2
    while len(out) < n:
        c = data[p]
        p += 1
        if (c & 0x80) == 0:
            # Literal run: (c & 0x7F) + 1 literal bytes follow.
            cnt = (c & 0x7F) + 1
            out += data[p:p + cnt]
            p += cnt
        else:
            # Back-reference: (c & 0x7F) + 1 bytes, 2-byte LE offset.
            cnt = (c & 0x7F) + 1
            off = data[p] | (data[p + 1] << 8)
            p += 2
            # Overlapping byte-by-byte copy (LZ77 semantics).
            for _ in range(cnt):
                out.append(out[-off])
    return bytes(out)

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    sys.stdout.buffer.write(decode(data))

if __name__ == '__main__':
    main()
PY
chmod +x /app/solve/decode.py
# Sanity: verify against the oracle on all corpus streams.
ok=0
for f in /app/corpus/*.bin; do
  /app/decompress "$f" > /tmp/exp.bin
  python3 /app/solve/decode.py "$f" > /tmp/got.bin
  if cmp -s /tmp/exp.bin /tmp/got.bin; then ok=$((ok+1)); fi
done
echo "corpus matches: $ok"
exit 0