#!/bin/bash
# Oracle for quiet-bridge: write the real decoder program, verify it on the
# provided sample, then run it to produce a sample output. Does not read /tests.
set -eu

cat > /app/decode.py <<'PY'
import sys, json

MAGIC = b"QBX7"

def decode(data):
    i = 0
    n = len(data)
    records = []
    discarded = 0
    while True:
        start = data.find(MAGIC, i)
        if start == -1:
            break
        # Need at least 7 header bytes (magic4 + len2 + seq1) to attempt parse.
        if start + 7 > n:
            discarded += 1
            i = start + 1
            continue
        length = data[start + 4] | (data[start + 5] << 8)
        seq = data[start + 6]
        cksum_pos = start + 7 + length
        if cksum_pos >= n:   # payload and/or checksum missing -> truncated
            discarded += 1
            i = start + 1
            continue
        payload = data[start + 7 : cksum_pos]
        stored = data[cksum_pos]
        calc = (sum(data[start : start + 7]) + sum(payload)) % 256
        if stored != calc:
            discarded += 1
            i = start + 1
            continue
        records.append({"seq": seq, "payload": payload})
        i = cksum_pos + 1
    records.sort(key=lambda r: r["seq"])  # stable ascending by sequence
    return {
        "discarded": discarded,
        "records": [
            {"seq": r["seq"], "text": r["payload"].decode("utf-8")}
            for r in records
        ],
    }

if __name__ == "__main__":
    import sys
    with open(sys.argv[1]) as fh:
        raw = fh.read()
    try:
        data = bytes.fromhex(" ".join(raw.split()))
    except ValueError:
        data = b""
    result = decode(data)
    with open(sys.argv[2], "w") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")
PY
chmod +x /app/decode.py

# Prove the tool works by running it against the provided sample.
python3 /app/decode.py /app/stream.hex /tmp/sample_output.json
echo "sample decoded: $(wc -c < /tmp/sample_output.json) bytes of output"