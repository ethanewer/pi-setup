#!/bin/bash
# Real oracle for blue-comet: writes the actual codec implementation, then
# exercises it on the visible sample to prove it runs. Never reads /tests.
set -eu

cat > /app/codec.py <<'PY'
import struct

MAGIC = b"BC7!"

def _decode_stream(data):
    out = bytearray()
    pos = 0
    n = len(data)
    while pos < n:
        if pos + 7 > n:
            raise ValueError("truncated block header")
        if data[pos:pos + 4] != MAGIC:
            raise ValueError("bad magic")
        plan = struct.unpack(">H", data[pos + 4:pos + 6])[0]
        flag = data[pos + 6]
        pos += 7
        if flag == 0x00:
            if pos + plan > n:
                raise ValueError("truncated literal block")
            out += data[pos:pos + plan]
            pos += plan
        elif flag == 0x01:
            produced = 0
            while produced < plan:
                if pos + 2 > n:
                    raise ValueError("truncated run pair")
                run, val = data[pos], data[pos + 1]
                pos += 2
                if run == 0:
                    raise ValueError("zero-length run")
                if produced + run > plan:
                    raise ValueError("run over-expands block")
                out.extend(bytes([val]) * run)
                produced += run
        else:
            raise ValueError("invalid flag byte")
    return bytes(out)


def decode(infile, outfile):
    with open(infile, "rb") as f:
        data = f.read()
    with open(outfile, "wb") as f:
        f.write(_decode_stream(data))


def encode(infile, outfile):
    with open(infile, "rb") as f:
        data = f.read()
    out = bytearray()
    for i in range(0, len(data), 65535):
        chunk = data[i:i + 65535]
        plan = len(chunk)
        out += MAGIC + struct.pack(">H", plan) + b"\x01"
        p = 0
        while p < plan:
            val = chunk[p]
            run = 1
            while p + run < plan and chunk[p + run] == val and run < 255:
                run += 1
            out.append(run)
            out.append(val)
            p += run
    with open(outfile, "wb") as f:
        f.write(out)
PY

# Prove the deliverable actually works by running it on the visible sample.
rm -rf /app/.solve_tmp
mkdir -p /app/.solve_tmp
python3 - <<'PY'
import sys
sys.path.insert(0, "/app")
import codec
codec.encode("/app/sample.txt", "/app/.solve_tmp/sample.enc")
codec.decode("/app/.solve_tmp/sample.enc", "/app/.solve_tmp/sample.dec")
assert open("/app/.solve_tmp/sample.dec", "rb").read() == open("/app/sample.txt", "rb").read()
print("oracle self-check passed: encode/decode of sample.txt is lossless")
PY
rm -rf /app/.solve_tmp