#!/usr/bin/env python3
"""echo-dial relay scanner.

Given an input directory, this program:
  1. locates the obfuscated intercept nodes by their exact naming convention,
     `encoded_<base64url, unpadded>` (the original filename is the decoded
     base64url segment),
  2. decodes each node: the file holds standard base64 of
     `plaintext_bytes XOR key_repeated`  (key == PASSWORD bytes, repeated),
  3. recovers the single operative secret word from the secret line
     `:::: VAULT-VERDICT :::: <token>`, normalised to lowercase alphanumerics,
  and writes `name.txt`, `plaintexts.txt` and `word.txt` into the output dir.

Runnable on any such directory (stdlib only).
"""
import base64
import os
import re
import sys

PASSWORD = "ardelle"
KEY = PASSWORD.encode("utf-8")

NAME_RE = re.compile(r"^encoded_([A-Za-z0-9_-]+)\Z")
MARK = re.compile(r"VAULT-VERDICT\s*::::\s*([A-Za-z0-9-]+)")


def decode_name(seg):
    """Original filename = base64url (unpadded) of the seg, padded to decode."""
    pad = (-len(seg)) % 4
    return base64.urlsafe_b64decode(seg + "=" * pad).decode("utf-8")


def decrypt_text(raw):
    data = base64.b64decode(raw.strip())
    return bytes(data[i] ^ KEY[i % len(KEY)] for i in range(len(data))).decode("utf-8")


def secret_of(text):
    m = MARK.search(text)
    if not m:
        return ""
    return "".join(c for c in m.group(1).lower() if c.isalnum())


def run(indir, outdir):
    os.makedirs(outdir, exist_ok=True)
    names, plains, word = [], [], ""
    for entry in sorted(os.listdir(indir)):
        m = NAME_RE.match(entry)
        if not m:
            continue
        fp = os.path.join(indir, entry)
        if not os.path.isfile(fp):
            continue
        try:
            with open(fp, "r", encoding="utf-8") as fh:
                raw = fh.read()
            name = decode_name(m.group(1))
            text = decrypt_text(raw)
        except Exception:
            continue
        text = text.rstrip("\r\n")
        names.append(name)
        plains.append(text)
        w = secret_of(text)
        if w and not word:
            word = w

    with open(os.path.join(outdir, "name.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(names))
        if names:
            fh.write("\n")
    with open(os.path.join(outdir, "plaintexts.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(plains))
        if plains:
            fh.write("\n")
    with open(os.path.join(outdir, "word.txt"), "w", encoding="utf-8") as fh:
        fh.write(word + "\n")
    print("ECHO-DIAL COMPLETE:DIR=%s FILES=%d" % (indir, len(names)))


if __name__ == "__main__":
    indir = sys.argv[1] if len(sys.argv) > 1 else "/app/relay"
    outdir = sys.argv[2] if len(sys.argv) > 2 else "/app"
    run(indir, outdir)