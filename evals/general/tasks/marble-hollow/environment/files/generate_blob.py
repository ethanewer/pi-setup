"""Deterministic visible blob generator (exact same expansion scheme as the
hidden fixtures): sha256 stream from a salted seed."""
import hashlib, sys

def stream(salt, n):
    out = bytearray()
    counter = 0
    while len(out) < n:
        out += hashlib.sha256(salt + b":" + str(counter).encode()).digest()
        counter += 1
    return bytes(out[:n])

if __name__ == "__main__":
    data = stream(b"nightly-observatory-snapshots", int(sys.argv[2]))
    with open(sys.argv[1], "wb") as f:
        f.write(data)
