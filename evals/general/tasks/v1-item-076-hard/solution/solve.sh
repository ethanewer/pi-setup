#!/bin/bash
# Oracle solution for item-076-hard: install decoder + encoder, verify round-trip.
set -e
mkdir -p /app/solve
cat > /app/solve/decode.py <<'PY'
import sys

def decode(data):
    # Header: 4-byte little-endian total output length.
    n = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24)
    out = bytearray()
    cur = 0
    nb = 0
    pos = 4

    def bit():
        nonlocal cur, nb, pos
        if nb == 0:
            cur = data[pos]
            pos += 1
            nb = 8
        b = cur & 1
        cur >>= 1
        nb -= 1
        return b

    def getn(k):
        v = 0
        for _ in range(k):
            v |= bit() << _   # LSB-first
        return v

    while len(out) < n:
        t = bit()
        if t == 0:
            out.append(getn(8))
        else:
            s = bit()
            if s == 0:                    # short back-ref
                off = getn(8) + 1
                ln = getn(2) + 2
            else:                         # long back-ref
                off = getn(16) + 1
                ln = getn(8) + 1
            for _ in range(ln):
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
cat > /app/solve/encode.py <<'PY'
import sys

def encode(data):
    out = bytearray()
    out += bytes([len(data) & 255, (len(data) >> 8) & 255,
                  (len(data) >> 16) & 255, (len(data) >> 24) & 255])
    bits = []
    def put(b):
        bits.append(b & 1)
    def putn(v, k):
        for _ in range(k):
            put(v >> _)
    def flush():
        while len(bits) % 8 != 0:
            bits.append(0)
        for i in range(0, len(bits), 8):
            b = 0
            for j in range(8):
                b |= bits[i + j] << j
            out.append(b & 255)
        bits.clear()
    sz = len(data)
    i = 0
    while i < sz:
        best_len, best_off = 0, 0
        if i > 0:
            lo = i - 4096 if i > 4096 else 0
            j = i - 1
            while j >= lo:
                k = 0
                while i + k < sz and data[j + k] == data[i + k] and k < 256:
                    k += 1
                if k >= 3 and k > best_len:
                    best_len, best_off = k, i - j
                if best_len >= 256:
                    break
                j -= 1
        if best_len >= 3:
            ln = min(best_len, 256)
            if ln <= 5 and best_off <= 256:
                put(1); put(0)
                putn(best_off - 1, 8)
                putn(ln - 2, 2)
            else:
                put(1); put(1)
                putn(best_off - 1, 16)
                putn(ln - 1, 8)
            i += ln
        else:
            put(0)
            putn(data[i], 8)
            i += 1
    flush()
    return bytes(out)

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    sys.stdout.buffer.write(encode(data))

if __name__ == '__main__':
    main()
PY
chmod +x /app/solve/decode.py /app/solve/encode.py
# Sanity: decode(corpus) must equal oracle; encode->oracle decode must round-trip.
ok=0
for f in /app/corpus/*.bin; do
  /app/decompress "$f" > /tmp/exp.bin
  python3 /app/solve/decode.py "$f" > /tmp/got.bin
  if cmp -s /tmp/exp.bin /tmp/got.bin; then ok=$((ok+1)); fi
done
for f in /app/corpus/*.txt; do
  python3 /app/solve/encode.py "$f" > /tmp/enc.bin
  /app/decompress /tmp/enc.bin > /tmp/dec.bin
  if cmp -s "$f" /tmp/dec.bin; then ok=$((ok+1)); fi
done
echo "sanity matches: $ok"
exit 0