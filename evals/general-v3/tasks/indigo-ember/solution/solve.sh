#!/bin/bash
# Real oracle for indigo-ember: write the recover.py tool, then RUN it on the
# shipped /app/station scenario to produce the deliverables. Never reads /tests.
set -eu

TOOL="/app/recover.py"

# ---- 1. Write the deliverable tool (this IS the work, not a canned answer).
cat > "$TOOL" <<'PY'
#!/usr/bin/env python3
"""Beacon-relay station recovery tool.

Usage:
    python3 recover.py <scenario_dir> <out_dir>

Reads cryptogram.txt, clue.json, keybox.enc and ciphertexts.txt from the
scenario directory, decodes the note, unlocks the key box with the passcode,
and decrypts every ciphertext block. Writes <out_dir>/key.txt and
<out_dir>/plaintexts.txt.
"""
import json
import os
import subprocess
import sys

ALPH = "abcdefghijklmnopqrstuvwxyz"
ROUNDS = 4
ADD = 0x7A3B
MASK = 0xFFFF


def rotl16(x, n):
    return ((x << n) | (x >> (16 - n))) & MASK


def rotr16(x, n):
    return ((x >> n) | (x << (16 - n))) & MASK


def enc_block(p, k):
    s = p & MASK
    for _ in range(ROUNDS):
        s = (s ^ k) & MASK
        s = rotl16(s, 3)
        s = (s + ADD) & MASK
    return s


def dec_block(c, k):
    s = c & MASK
    for _ in range(ROUNDS):
        s = (s - ADD) & MASK
        s = rotr16(s, 3)
        s = (s ^ k) & MASK
    return s


def decode_cryptogram(text, clue):
    """Apply the clued substitution to every character, preserving case."""
    plain = clue["plain_alphabet"]
    cipher = clue["cipher_alphabet"]
    lut = {}
    for i, c in enumerate(cipher):
        lut[c.lower()] = plain[i].lower()
    out = []
    for ch in text:
        low = ch.lower()
        if low in lut:
            dec = lut[low]
            out.append(dec.upper() if ch.isupper() else dec)
        else:
            out.append(ch)
    return "".join(out)


def extract_passcode(note):
    """Value right after PASS=; ends at space, comma, newline, or end of note."""
    idx = note.find("PASS=")
    if idx < 0:
        return ""
    rest = note[idx + len("PASS="):]
    value = []
    for ch in rest:
        if ch in (" ", ",", "\n", "\r", "\t"):
            break
        value.append(ch)
    return "".join(value)


def decrypt_keybox(path, passcode):
    r = subprocess.run(
        ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
         "-pass", "pass:" + passcode, "-in", path],
        capture_output=True, check=True)
    for line in r.stdout.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if line.startswith("key="):
            return line[len("key="):].strip()
    raise ValueError("key box did not contain a key= line")


def recover(scenario_dir, out_dir):
    with open(os.path.join(scenario_dir, "clue.json"), "r", encoding="utf-8") as fh:
        clue = json.load(fh)
    with open(os.path.join(scenario_dir, "cryptogram.txt"), "r", encoding="utf-8") as fh:
        encoded = fh.read()
    note = decode_cryptogram(encoded, clue)
    passcode = extract_passcode(note)
    if not passcode:
        raise ValueError("no PASS= passcode found in decoded note")
    key_hex = decrypt_keybox(os.path.join(scenario_dir, "keybox.enc"), passcode)
    key = int(key_hex, 16)

    plaintexts = []
    with open(os.path.join(scenario_dir, "ciphertexts.txt"), "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            block = int(line, 16)
            p = dec_block(block, key)
            plaintexts.append(chr((p >> 8) & 0xFF) + chr(p & 0xFF))

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "key.txt"), "w", encoding="utf-8") as fh:
        fh.write("key=%s\n" % key_hex.lower())
    with open(os.path.join(out_dir, "plaintexts.txt"), "w", encoding="utf-8") as fh:
        for pt in plaintexts:
            fh.write(pt + "\n")
    return key_hex, plaintexts


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: recover.py <scenario_dir> <out_dir>\n")
        return 2
    recover(sys.argv[1], sys.argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$TOOL"

# ---- 2. Run the tool on the shipped scenario to land the deliverables.
python3 "$TOOL" /app/station /app

echo "solve.sh done -> $TOOL /app/key.txt /app/plaintexts.txt"
ls -l "$TOOL" /app/key.txt /app/plaintexts.txt
