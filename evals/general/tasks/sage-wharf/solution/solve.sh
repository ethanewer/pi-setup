#!/usr/bin/env bash
# Real solution: install the general-purpose reconstructor, then run it to
# produce the reconstruction report from the evidence.
set -euo pipefail
cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""Master artifact reconstructor for the Grimwater Docks forensic image."""
import sys, os, base64, hashlib, re, json

TOTAL = 32896            # total of the symbol frequency model
def _cum(s): return s*(s+1)//2          # cumulative freq before symbol s
def _freq(s): return s+1                # frequency of symbol s

# ---------------- 1. range coder ----------------
def rc_encode(data):
    low, high = 0, 0xFFFFFFFF
    out = bytearray()
    def scale():
        nonlocal low, high
        while (low ^ high) & 0xFF000000 == 0:
            out.append((low >> 24) & 0xFF)
            low = (low << 8) & 0xFFFFFFFF
            high = ((high << 8) | 0xFF) & 0xFFFFFFFF
    for b in data:
        rng = high - low + 1
        lo = low + (_cum(b) * rng) // TOTAL
        hi = low + ((_cum(b) + _freq(b)) * rng) // TOTAL - 1
        low, high = lo, hi
        scale()
    for i in range(4):
        out.append((high >> (24 - 8*i)) & 0xFF)
    return len(data).to_bytes(4, 'big') + bytes(out)

def rc_decode(blob):
    n = int.from_bytes(blob[:4], 'big')
    body = blob[4:]
    idx = 0
    def nextb():
        nonlocal idx
        v = body[idx]; idx += 1; return v
    low, high = 0, 0xFFFFFFFF
    code = 0
    for _ in range(4):
        code = (code << 8) | nextb()
    out = bytearray()
    def scale():
        nonlocal low, high, code
        while (low ^ high) & 0xFF000000 == 0:
            low = (low << 8) & 0xFFFFFFFF
            high = ((high << 8) | 0xFF) & 0xFFFFFFFF
            code = ((code << 8) | nextb()) & 0xFFFFFFFF
    for _ in range(n):
        rng = high - low + 1
        scaled = ((code - low + 1) * TOTAL - 1) // rng
        s = 0
        while _cum(s+1) <= scaled:
            s += 1
        out.append(s)
        lo = low + (_cum(s) * rng) // TOTAL
        hi = low + ((_cum(s) + _freq(s)) * rng) // TOTAL - 1
        low, high = lo, hi
        scale()
    return bytes(out)

# ---------------- 2. sentinel obfuscation ----------------
SXOR = 0x2B
def sentinel_unobfuscate(payload):
    s2 = bytes(b ^ SXOR for b in payload)
    s1 = base64.b64decode(s2)
    return s1[::-1].decode('utf-8')

def sentinels_unpack(blob):
    cmds = []
    i = 0
    while i < len(blob):
        ln = int.from_bytes(blob[i:i+4], 'big')
        i += 4
        cmds.append(sentinel_unobfuscate(blob[i:i+ln]))
        i += ln
    return cmds

# ---------------- 3. WAL transform ----------------
WAL_MAGICS = {0x377f0682, 0x377f0683}
def wal_report(path):
    with open(path, 'rb') as fh:
        head = fh.read(8)
    if len(head) < 8:
        return "NONE"
    m = int.from_bytes(head[:4], 'big')
    if m in WAL_MAGICS:
        return "NONE"
    for k in range(256):
        if int.from_bytes(bytes(b ^ k for b in head[:4]), 'big') in WAL_MAGICS:
            return "KEY=%d" % k
    return "NONE"

# ---------------- 4. digest chain ----------------
def digest_chain(P):
    h1 = hashlib.sha256(P).digest()
    h2 = hashlib.sha1(h1[:20]).digest()
    h3 = hashlib.md5(h1[12:28] + h2).digest()
    return hashlib.sha256(h3 + P).hexdigest()

# ---------------- evidence reconstruction ----------------
EVIDENCE = "/app/evidence"
def solve_evidence():
    log_rd = open(os.path.join(EVIDENCE, "logbook.bin"), 'rb').read()
    log_plain = rc_decode(log_rd)
    secret_m = re.search(rb'secret = (\S+)', log_plain)
    secret = secret_m.group(1).decode() if secret_m else ""
    sent_cmds = sentinels_unpack(open(os.path.join(EVIDENCE, "sentries.bin"), 'rb').read())
    wal = wal_report(os.path.join(EVIDENCE, "harbor.db-wal"))
    ans = {
        "log_plaintext_hex": log_plain.hex(),
        "secret": secret,
        "sentinel_commands": sent_cmds,
        "wal_transform": wal,
        "digest": digest_chain(log_plain),
    }
    with open("/app/answer.json", 'w') as fh:
        json.dump(ans, fh, indent=2)
    return ans

def main(argv):
    if len(argv) >= 2 and argv[1] == "solve-evidence":
        solve_evidence(); return 0
    cmd = argv[1]
    if cmd == "decode":
        sys.stdout.buffer.write(rc_decode(open(argv[2], 'rb').read()))
    elif cmd == "encode":
        sys.stdout.buffer.write(rc_encode(open(argv[2], 'rb').read()))
    elif cmd == "unobfuscate":
        sys.stdout.write(sentinel_unobfuscate(open(argv[2], 'rb').read()))
    elif cmd == "wal-report":
        sys.stdout.write(wal_report(argv[2]))
    elif cmd == "digest":
        sys.stdout.write(digest_chain(open(argv[2], 'rb').read()))
    else:
        sys.stderr.write("unknown cmd\n"); return 2
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/solve.py
python3 /app/solve.py solve-evidence
ls -l /app/solve.py /app/answer.json
