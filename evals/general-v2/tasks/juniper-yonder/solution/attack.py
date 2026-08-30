#!/usr/bin/env python3
"""
YONDER crypto-lab solver.

Usage:
    python3 attack.py <scenario_dir> <out_dir>

Given a scenario directory it:
  1. recovers the reduced-cipher low-bit round keys by a chosen-plaintext
     differential probe against <scenario>/yonder_enc (an oracle binary whose
     key is hidden),
  2. decrypts every ciphertext in <scenario>/ciphertexts.txt, writing one
     plaintext per line to <out_dir>/plaintexts.txt,
  3. recovers the key bytes to <out_dir>/keys,
  4. decodes the base64-obfuscated filenames under <scenario>/encoded/ and
     writes them (sorted) to <out_dir>/decoded_names.txt,
  5. decodes the substitution cryptogram with <scenario>/clue.json, extracting
     the PASS= passcode and the SECRET= secret word,
  6. runs the installed AES-256-CBC CLI (openssl) over every file in
     <scenario>/src/, mirroring the tree to <out_dir>/encsrc/ using the
     passcode, and
  7. writes the normalized secret word to <out_dir>/name.txt.

Importable: recover_key(oracle) returns (k0,k1) given an encrypt callback.
"""
import os
import sys
import json
import base64
import subprocess
import string

# ---- reduced cipher (S-box is a fixed public constant of the scheme) ----
SBOX = [33, 113, 15, 65, 203, 130, 163, 49, 232, 10, 74, 240, 212, 91, 179, 142, 51, 103, 194, 182, 244, 104, 223, 108, 160, 229, 55, 158, 219, 168, 128, 69, 1, 189, 26, 245, 201, 23, 27, 242, 252, 126, 122, 20, 214, 40, 72, 114, 180, 92, 48, 11, 54, 17, 98, 231, 239, 42, 146, 70, 190, 198, 170, 207, 211, 124, 12, 85, 134, 155, 29, 202, 95, 21, 0, 64, 61, 255, 46, 7, 53, 60, 197, 2, 169, 82, 116, 133, 186, 88, 173, 32, 150, 247, 249, 216, 121, 9, 145, 63, 152, 5, 188, 50, 200, 100, 129, 84, 236, 153, 137, 105, 215, 220, 154, 110, 222, 115, 164, 43, 99, 183, 45, 52, 102, 80, 221, 210, 76, 78, 57, 93, 234, 36, 166, 156, 253, 196, 13, 144, 233, 106, 205, 97, 131, 165, 111, 193, 56, 243, 62, 71, 109, 119, 248, 75, 157, 217, 254, 25, 237, 191, 136, 127, 159, 148, 86, 218, 208, 147, 30, 19, 94, 39, 204, 176, 250, 175, 101, 120, 192, 35, 167, 174, 117, 143, 24, 185, 187, 238, 241, 83, 181, 195, 37, 209, 177, 31, 132, 141, 225, 118, 77, 224, 28, 8, 140, 58, 125, 199, 16, 123, 230, 81, 135, 6, 44, 172, 226, 171, 47, 38, 87, 41, 178, 227, 151, 228, 112, 162, 246, 139, 184, 73, 67, 235, 161, 149, 90, 18, 4, 79, 3, 59, 206, 14, 66, 68, 22, 34, 89, 107, 138, 96, 213, 251]
INVBOX = [74, 32, 83, 242, 240, 101, 215, 79, 205, 97, 9, 51, 66, 138, 245, 2, 210, 53, 239, 171, 43, 73, 248, 37, 186, 159, 34, 38, 204, 70, 170, 197, 91, 0, 249, 181, 133, 194, 221, 173, 45, 223, 57, 119, 216, 122, 78, 220, 50, 7, 103, 16, 123, 80, 52, 26, 148, 130, 207, 243, 81, 76, 150, 99, 75, 3, 246, 234, 247, 31, 59, 151, 46, 233, 10, 155, 128, 202, 129, 241, 125, 213, 85, 191, 107, 67, 166, 222, 89, 250, 238, 13, 49, 131, 172, 72, 253, 143, 54, 120, 105, 178, 124, 17, 21, 111, 141, 251, 23, 152, 115, 146, 228, 1, 47, 117, 86, 184, 201, 153, 179, 96, 42, 211, 65, 208, 41, 163, 30, 106, 5, 144, 198, 87, 68, 214, 162, 110, 252, 231, 206, 199, 15, 185, 139, 98, 58, 169, 165, 237, 92, 226, 100, 109, 114, 69, 135, 156, 27, 164, 24, 236, 229, 6, 118, 145, 134, 182, 29, 84, 62, 219, 217, 90, 183, 177, 175, 196, 224, 14, 48, 192, 19, 121, 232, 187, 88, 188, 102, 33, 60, 161, 180, 147, 18, 193, 137, 82, 61, 209, 104, 36, 71, 4, 174, 142, 244, 63, 168, 195, 127, 64, 12, 254, 44, 112, 95, 157, 167, 28, 113, 126, 116, 22, 203, 200, 218, 225, 227, 25, 212, 55, 8, 140, 132, 235, 108, 160, 189, 56, 11, 190, 39, 149, 20, 35, 230, 93, 154, 94, 176, 255, 40, 136, 158, 77]

def _f(x, k):
    return SBOX[(x ^ k) & 0xff]

def encrypt_block(P, k0, k1):
    L = (P >> 8) & 0xff; R = P & 0xff
    L1, R1 = R, L ^ _f(R, k0)
    L2, R2 = R1, L1 ^ _f(R1, k1)
    return (L2 << 8) | R2

def decrypt_block(C, k0, k1):
    L2c = (C >> 8) & 0xff; R2c = C & 0xff
    R1 = L2c
    R0 = R2c ^ _f(R1, k1)
    L0 = R1 ^ _f(R0, k0)
    return (L0 << 8) | R0

def recover_key(oracle):
    """
    Chosen-plaintext differential key recovery against an encrypt callback
    oracle(p)->ciphertext.  The reduced cipher leaks the round-1 state in the
    high output byte, so two chosen plaintexts (a base probe and a
    difference-confirming probe) pin the two low-bit round keys k0 and k1
    exactly.  oracle is called with chosen plaintext values (differentials).
    Returns (k0, k1).
    """
    S0 = INVBOX
    def one(L0, R0):
        C = oracle((L0 << 8) | R0)
        high = (C >> 8) & 0xff
        low = C & 0xff
        rk0 = R0 ^ S0[L0 ^ high]
        rk1 = high ^ S0[R0 ^ low]
        return rk0, rk1
    a = one(0, 0x2b)
    b = one(0x53, 0x9f)          # second, difference-confirming chosen plaintext
    if a != b:
        # fall back to a third differential probe if anything is inconsistent
        a = one(0x2c, 0x71)
    return a

def _oracle_binary(path):
    def oracle(P):
        r = subprocess.run([path], input="%04x\n" % P,
                           capture_output=True, text=True, check=True)
        return int(r.stdout.strip(), 16)
    return oracle

def _b64url_decode(name):
    pad = "=" * (-len(name) % 4)
    raw = base64.urlsafe_b64decode(name + pad)
    return raw.decode("utf-8")

def _normalize(s):
    return "".join(ch for ch in s.strip().lower() if ch not in string.whitespace)

def _extract_token(field, text):
    idx = text.upper().find(field)
    if idx < 0:
        return ""
    rest = text[idx + len(field):]
    i = 0
    while i < len(rest) and rest[i] not in " \t\r\n,":
        i += 1
    return rest[:i].strip()

def _openssl_encrypt(src, dst, passcode):
    subprocess.run(["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-salt",
                    "-pass", "pass:" + passcode, "-in", src, "-out", dst],
                   check=True, capture_output=True)

def run_scenario(inc, out):
    os.makedirs(out, exist_ok=True)
    oracle = _oracle_binary(os.path.join(inc, "yonder_enc"))

    # 1+3) recover keys
    k0, k1 = recover_key(oracle)
    key_hex = "%02x%02x" % (k0, k1)
    with open(os.path.join(out, "keys"), "w") as f:
        f.write("k0=%02x\nk1=%02x\nkey=%s\n" % (k0, k1, key_hex))

    # 2) decrypt ciphertexts, one plaintext per line
    with open(os.path.join(inc, "ciphertexts.txt")) as f:
        cts = [int(x.strip(), 16) for x in f if x.strip()]
    plain = []
    for C in cts:
        P = decrypt_block(C, k0, k1)
        plain.append(chr((P >> 8) & 0xff) + chr(P & 0xff))
    with open(os.path.join(out, "plaintexts.txt"), "w") as f:
        f.write("\n".join(plain) + ("\n" if plain else ""))

    # 4) base64-obfuscated filenames
    encdir = os.path.join(inc, "encoded")
    names = []
    if os.path.isdir(encdir):
        for fn in os.listdir(encdir):
            p = os.path.join(encdir, fn)
            if os.path.isfile(p):
                try:
                    names.append(_b64url_decode(fn))
                except Exception:
                    continue
    names.sort()
    with open(os.path.join(out, "decoded_names.txt"), "w") as f:
        f.write("\n".join(names) + ("\n" if names else ""))

    # 5) cryptogram -> passcode + secret
    ct_text = open(os.path.join(inc, "cryptogram.txt")).read()
    table = json.load(open(os.path.join(inc, "clue.json")))["decodes_letter_to"]
    note = "".join((table[c.lower()] if c.islower() and c.lower() in table
                    else (table[c.lower()].upper() if c.isupper() and c.lower() in table
                    else c)) for c in ct_text)
    passcode = _extract_token("PASS=", note)
    secret = _extract_token("SECRET=", note)

    # 6) run crypto CLI over every file in src/
    srcdir = os.path.join(inc, "src")
    if os.path.isdir(srcdir):
        for rel in os.listdir(srcdir):
            pass
        for root, dirs, files in os.walk(srcdir):
            for fn in sorted(files):
                sp = os.path.join(root, fn)
                rel = os.path.relpath(sp, srcdir)
                dp = os.path.join(out, "encsrc", rel)
                os.makedirs(os.path.dirname(dp) or out, exist_ok=True)
                _openssl_encrypt(sp, dp, passcode)

    # 7) normalized secret word
    with open(os.path.join(out, "name.txt"), "w") as f:
        f.write(_normalize(secret))

    with open(os.path.join(out, "passcode.txt"), "w") as f:
        f.write(passcode)

def main():
    if len(sys.argv) != 3:
        sys.exit("usage: attack.py <scenario_dir> <out_dir>")
    run_scenario(sys.argv[1], sys.argv[2])
    print("YONDER done")

if __name__ == "__main__":
    main()
