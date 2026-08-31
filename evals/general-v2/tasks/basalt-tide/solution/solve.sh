#!/bin/bash
# Oracle for basalt-tide: author recover.py, start the local daemon on the
# visible seed, run the recovery, and write /app/recovery.json. From a
# pristine container.
set -eu

cat > /app/recover.py <<'PY_EOF'
#!/usr/bin/env python3
"""basalt-tide key recovery.

Recover the 16-bit seed of the running cipher daemon with 2 chosen-plaintext
queries, then brute-force the seed space with an incrementally-pruned search:

  Query 1: p[i] = i          -> rec[i] = S[i] ^ M[i mod 4]
  Query 2: p[i] = 0          -> z[i]   = S[0] ^ M[i mod 4]
  => d[j] = z[j] ^ z[0] = M[j] ^ M[0]  (secret mask up to a global constant)

For a candidate seed, g[i] := S_seed[i] ^ rec[i] must equal M[i mod 4]; the
unknown global constant cancels in g[i] ^ g[i'] = d[i%4] ^ d[i'%4].

Crucially, in a backwards Fisher-Yates the entries S[i..255] are FINAL once
step i has run, so the pairwise consistency checks can be applied DURING
construction: a wrong seed is rejected after ~2 of the 255 steps on average,
which keeps the full 65536-seed sweep far inside the time budget (a naive
build-then-check sweep would take minutes).
"""
import json
import socket
import sys
import time

PORT = 46071


def xorshift16(x):
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF


class Oracle:
    def __init__(self, port=PORT):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.fh = self.sock.makefile("rwb")
        self.n = 0

    def query(self, data):
        self.fh.write(data.hex().encode() + b"\n")
        self.fh.flush()
        line = self.fh.readline().strip()
        if not line or line.startswith(b"ERR"):
            raise RuntimeError("oracle error: %r" % line)
        self.n += 1
        return bytes.fromhex(line.decode())


def main():
    t0 = time.time()
    o = Oracle()
    rec = o.query(bytes(range(256)))   # rec[i] = S[i] ^ M[i%4]
    z = o.query(bytes(256))            # z[i]   = S[0] ^ M[i%4]
    d = [z[j] ^ z[0] for j in range(4)]
    dd = [d[i % 4] ^ d[(i + 1) % 4] for i in range(256)]

    seed_found = None
    sbox = None
    for seed in range(65536):
        s = list(range(256))
        x = seed
        ok = True
        for i in range(255, 0, -1):
            x = xorshift16(x)
            j = x % (i + 1)
            s[i], s[j] = s[j], s[i]
            if i <= 254:
                # s[i] and s[i+1] are both final now
                if (s[i] ^ rec[i]) ^ (s[i + 1] ^ rec[i + 1]) != dd[i]:
                    ok = False
                    break
        if not ok:
            continue
        g0 = s[0] ^ rec[0]
        if all((s[i] ^ rec[i]) ^ g0 == d[i % 4] for i in range(1, 256)):
            seed_found = seed
            sbox = s
            break

    elapsed_ms = int((time.time() - t0) * 1000)
    if seed_found is None:
        print("recovery failed")
        return 1
    result = {
        "task": "basalt-tide",
        "seed": "%04x" % seed_found,
        "sbox": bytes(sbox).hex(),
        "queries": o.n,
        "elapsed_ms": elapsed_ms,
        "ok": True,
    }
    with open("/app/recovery.json", "w") as fh:
        json.dump(result, fh, indent=1)
    print("recovered seed=%s queries=%d elapsed_ms=%d"
          % (result["seed"], o.n, elapsed_ms))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY_EOF
chmod +x /app/recover.py

# Start the daemon on the visible seed and produce the visible deliverable.
pkill -f "cipher_service.py" 2>/dev/null || true
sleep 0.3
rm -f /tmp/.basalt_tide_queries
nohup python3 /app/cipher_service.py --serve >/tmp/bt_daemon.log 2>&1 &
for i in $(seq 1 50); do
  if python3 -c "import socket;socket.create_connection(('127.0.0.1',46071),timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

python3 /app/recover.py
echo "basalt-tide solve done"
cat /app/recovery.json
