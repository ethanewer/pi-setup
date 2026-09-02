#!/usr/bin/env python3
"""basalt-tide cipher oracle — a byte-substitution cipher with a secret key.

The cipher is fully public EXCEPT the secret 16-bit seed (the "key"):

    def xorshift16(x):            # x != 0
        x ^= (x << 7) & 0xFFFF
        x ^= x >> 9
        x ^= (x << 8) & 0xFFFF
        return x & 0xFFFF

    S = list(range(256))          # the S-box
    x = seed
    for i in range(255, 0, -1):   # backwards Fisher-Yates
        x = xorshift16(x)
        j = x % (i + 1)
        S[i], S[j] = S[j], S[i]

    M[j] = S[200 + j] for j in 0..3   # secret 4-byte position mask

Encryption of a plaintext buffer p (length L, 1 <= L <= 512 bytes):

    c[i] = S[p[i]] XOR M[i mod 4]

The seed is never exposed by the oracle; you may only observe ciphertexts of
plaintexts you choose.

Interfaces
----------
Library (uses the visible seed file /app/.cipher_seed):

    import cipher_service
    eng = cipher_service.Engine()
    eng.query("00ff...")   # hex in, hex out

CLI (same seed source):

    python3 cipher_service.py <hex-plaintext>   # prints hex ciphertext

Daemon (the verifier starts it with an EPHEMERAL secret):

    python3 cipher_service.py --serve [--port 46071]

    The daemon takes its seed from the file named by the CIPHER_KEYFILE
    environment variable (it reads and DELETES that file at startup), falling
    back to /app/.cipher_seed. Line protocol on 127.0.0.1:<port>: send a hex
    plaintext line, receive a hex ciphertext line; send "CLOSE" to end the
    connection (the daemon keeps serving).

Every query appends one line to /tmp/.basalt_tide_queries (query accounting;
a per-daemon cap of 1024 queries is enforced).
"""

import os
import socket
import sys

QUERY_LOG = "/tmp/.basalt_tide_queries"
SEED_FILE = "/app/.cipher_seed"
DEFAULT_PORT = 46071
MAX_PT_BYTES = 512
MAX_QUERIES = 1024


def xorshift16(x):
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x & 0xFFFF


def derive_sbox(seed):
    """The documented S-box for a 16-bit seed (0..65535)."""
    S = list(range(256))
    x = seed & 0xFFFF
    for i in range(255, 0, -1):
        x = xorshift16(x)
        j = x % (i + 1)
        S[i], S[j] = S[j], S[i]
    return S


def derive_mask(S):
    return [S[200 + j] for j in range(4)]


def _count_query():
    try:
        with open(QUERY_LOG, "a") as fh:
            fh.write("q\n")
    except OSError:
        pass


def _queries_so_far():
    try:
        with open(QUERY_LOG) as fh:
            return sum(1 for _ in fh)
    except OSError:
        return 0


def load_seed():
    kf = os.environ.get("CIPHER_KEYFILE")
    if kf:
        with open(kf) as fh:
            seed = int(fh.read().strip(), 16)
        try:
            os.remove(kf)
        except OSError:
            pass
        return seed & 0xFFFF
    with open(SEED_FILE) as fh:
        return int(fh.read().strip(), 16) & 0xFFFF


class Engine:
    """Library-mode oracle over the visible seed file."""

    def __init__(self, seed=None):
        self.seed = load_seed() if seed is None else (seed & 0xFFFF)
        self.S = derive_sbox(self.seed)
        self.M = derive_mask(self.S)

    def encrypt_bytes(self, p):
        if not (1 <= len(p) <= MAX_PT_BYTES):
            raise ValueError("plaintext must be 1..%d bytes" % MAX_PT_BYTES)
        if _queries_so_far() >= MAX_QUERIES:
            raise RuntimeError("query budget exceeded")
        _count_query()
        return bytes(self.S[b] ^ self.M[i % 4] for i, b in enumerate(p))

    def query(self, hex_plain):
        return self.encrypt_bytes(bytes.fromhex(hex_plain)).hex()


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == "--serve":
        port = DEFAULT_PORT
        if "--port" in argv:
            port = int(argv[argv.index("--port") + 1])
        seed = load_seed()
        S = derive_sbox(seed)
        M = derive_mask(S)
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", port))
        srv.listen(16)
        print("cipher_service: serving on 127.0.0.1:%d" % port, flush=True)
        while True:
            conn, _ = srv.accept()
            try:
                fh = conn.makefile("rwb")
                for raw in fh:
                    line = raw.strip()
                    if not line or line.upper() == b"CLOSE":
                        break
                    if _queries_so_far() >= MAX_QUERIES:
                        fh.write(b"ERR query budget exceeded\n")
                        fh.flush()
                        break
                    try:
                        p = bytes.fromhex(line.decode())
                        if not (1 <= len(p) <= MAX_PT_BYTES):
                            raise ValueError
                        _count_query()
                        c = bytes(S[b] ^ M[i % 4] for i, b in enumerate(p))
                        fh.write(c.hex().encode() + b"\n")
                    except Exception:
                        fh.write(b"ERR bad request\n")
                    fh.flush()
            except OSError:
                pass
            finally:
                try:
                    conn.close()
                except OSError:
                    pass
        return

    # CLI mode: python3 cipher_service.py <hex>
    if len(argv) != 1:
        print("usage: cipher_service.py <hex> | --serve [--port N]")
        return 2
    eng = Engine()
    print(eng.query(argv[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
