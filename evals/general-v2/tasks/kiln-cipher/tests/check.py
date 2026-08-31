#!/usr/bin/env python3
"""Verifier for kiln-cipher (executes-deliverable).

EXECUTES the deliverable /app/mkcert.py on every hidden identity case under
/tests/hidden (unseen CN / key size / fresh out-dir) and validates each staged
bundle with openssl: PEM block order and count in bundle.pem, standalone parse
of each extracted block, key/cert public-key match, CN match, key size, 0600
modes, and the DER-sha256 fingerprint. Also validates the visible identity in
/app/identity against /app/staging/identity-spec.toml. Every parse is guarded.
"""
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

APP = "/app"
MKCERT = os.path.join(APP, "mkcert.py")
IDENTITY = os.path.join(APP, "identity")
SPEC = os.path.join(APP, "staging", "identity-spec.toml")
HIDDEN = "/tests/hidden"

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg, flush=True)


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60)


def pem_blocks(text):
    """Split concatenated PEM text into (label, body) blocks; strict armor."""
    blocks = []
    idx = 0
    pat = re.compile(
        r"-----BEGIN ([A-Z0-9 ]+)-----\n(.*?)-----END \1-----\n?", re.S)
    pos = 0
    while pos < len(text):
        m = pat.search(text, pos)
        if not m:
            # only whitespace may remain
            if text[pos:].strip():
                return None
            break
        if text[pos:m.start()].strip():
            return None  # non-whitespace junk between blocks
        blocks.append((m.group(1), m.group(2)))
        pos = m.end()
    return blocks


def write_block(block, path):
    label, body = block
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("-----BEGIN %s-----\n" % label)
        fh.write(body)
        if not body.endswith("\n"):
            fh.write("\n")
        fh.write("-----END %s-----\n" % label)


def is_private_key_label(label):
    return label.endswith("PRIVATE KEY")


def validate_staged(out_dir, cn, bits, tag):
    key = os.path.join(out_dir, "key.pem")
    cert = os.path.join(out_dir, "cert.pem")
    bundle = os.path.join(out_dir, "bundle.pem")
    fp = os.path.join(out_dir, "fingerprint.txt")
    for p in (key, cert, bundle, fp):
        if not os.path.isfile(p):
            fail("%s: missing %s" % (tag, p))
            return

    # --- individual parses ---
    r = sh(["openssl", "pkey", "-in", key, "-noout"])
    if r.returncode != 0:
        fail("%s: key.pem does not parse (%s)" % (tag, r.stderr[-200:]))
        return
    r = sh(["openssl", "x509", "-in", cert, "-noout"])
    if r.returncode != 0:
        fail("%s: cert.pem does not parse (%s)" % (tag, r.stderr[-200:]))
        return

    # --- CN, validity, key size ---
    r = sh(["openssl", "x509", "-in", cert, "-noout", "-subject"])
    if r.returncode != 0 or ("CN=%s" % cn) not in r.stdout:
        fail("%s: cert subject CN mismatch (got %r)" % (tag, r.stdout.strip()))
    r = sh(["openssl", "x509", "-in", cert, "-checkend", "0", "-noout"])
    if r.returncode != 0:
        fail("%s: certificate is not currently valid" % tag)
    r = sh(["openssl", "pkey", "-in", key, "-text", "-noout"])
    if r.returncode != 0 or ("Private-Key: (%d bit" % bits) not in r.stdout:
        fail("%s: key size is not %d bits" % (tag, bits))

    # --- public key match: key vs cert ---
    tmp = tempfile.mkdtemp(prefix="kiln_cipher_key_")
    try:
        pub1 = os.path.join(tmp, "k.pub")
        r = sh(["openssl", "pkey", "-in", key, "-pubout", "-out", pub1])
        if r.returncode != 0:
            fail("%s: cannot extract key public key" % tag)
            return
        h1 = sh(["openssl", "md5", pub1]).stdout.split()[-1]
        r2 = subprocess.run(
            "openssl x509 -in '%s' -pubkey -noout | openssl md5" % cert,
            shell=True, capture_output=True, text=True, timeout=60)
        if r2.returncode != 0:
            fail("%s: cannot extract cert public key" % tag)
            return
        h2 = r2.stdout.split()[-1]
        if h1 != h2:
            fail("%s: certificate public key does not match the private key"
                 % tag)

        # --- the combined bundle ---
        with open(bundle, "r", encoding="utf-8") as fh:
            blocks = pem_blocks(fh.read())
        if blocks is None:
            fail("%s: bundle.pem contains non-PEM junk" % tag)
            return
        if len(blocks) != 2:
            fail("%s: bundle.pem has %d PEM blocks, want exactly 2"
                 % (tag, len(blocks)))
            return
        if not is_private_key_label(blocks[0][0]):
            fail("%s: bundle.pem first block is %r, want a private key"
                 % (tag, blocks[0][0]))
            return
        if blocks[1][0] != "CERTIFICATE":
            fail("%s: bundle.pem second block is %r, want CERTIFICATE"
                 % (tag, blocks[1][0]))
            return

        # each bundled block must parse standalone
        b_key = os.path.join(tmp, "b_key.pem")
        b_cert = os.path.join(tmp, "b_cert.pem")
        write_block(blocks[0], b_key)
        write_block(blocks[1], b_cert)
        r = sh(["openssl", "pkey", "-in", b_key, "-noout"])
        if r.returncode != 0:
            fail("%s: bundle key block does not parse (%s)"
                 % (tag, r.stderr[-200:]))
            return
        r = sh(["openssl", "x509", "-in", b_cert, "-noout"])
        if r.returncode != 0:
            fail("%s: bundle cert block does not parse (%s)"
                 % (tag, r.stderr[-200:]))
            return
        r = sh(["openssl", "x509", "-in", b_cert, "-noout", "-subject"])
        if ("CN=%s" % cn) not in r.stdout:
            fail("%s: bundled cert CN mismatch (got %r)"
                 % (tag, r.stdout.strip()))
        # bundled key/cert must match the standalone files
        hb1 = subprocess.run(
            ["openssl", "pkey", "-in", b_key, "-pubout", "-outform", "DER"],
            capture_output=True, timeout=60)
        hb2 = subprocess.run(
            ["openssl", "pkey", "-in", key, "-pubout", "-outform", "DER"],
            capture_output=True, timeout=60)
        if (hb1.returncode != 0 or hb2.returncode != 0 or
                hashlib.sha256(hb1.stdout).digest() !=
                hashlib.sha256(hb2.stdout).digest()):
            fail("%s: bundled key differs from key.pem" % tag)
        with open(b_cert, "rb") as fh1, open(cert, "rb") as fh2:
            if (hashlib.sha256(fh1.read()).digest() !=
                    hashlib.sha256(fh2.read()).digest()):
                fail("%s: bundled cert differs from cert.pem" % tag)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- modes ---
    for p in (key, bundle):
        mode = stat.S_IMODE(os.stat(p).st_mode)
        if mode != 0o600:
            fail("%s: %s mode is %o, want 600" % (tag, p, mode))

    # --- fingerprint ---
    r = subprocess.run(
        "openssl x509 -in '%s' -outform DER | sha256sum" % cert,
        shell=True, capture_output=True, text=True, timeout=60)
    want_fp = r.stdout.split()[0].strip().lower()
    with open(fp, "r", encoding="utf-8") as fh:
        got_fp = fh.read().strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", got_fp):
        fail("%s: fingerprint.txt is not 64 lowercase hex chars" % tag)
    elif got_fp != want_fp:
        fail("%s: fingerprint mismatch" % tag)


def load_spec_cn():
    cn, bits = None, None
    try:
        with open(SPEC, "r", encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r'\s*common_name\s*=\s*"([^"]+)"', line)
                if m:
                    cn = m.group(1)
                m = re.match(r"\s*key_bits\s*=\s*(\d+)", line)
                if m:
                    bits = int(m.group(1))
    except Exception as exc:
        fail("cannot read staging spec: %s" % exc)
    return cn, bits


def main():
    if not os.path.isfile(MKCERT):
        fail("missing /app/mkcert.py")
        return 1

    # --- visible identity (provisioned by the agent per the staging spec) ---
    cn, bits = load_spec_cn()
    if cn is None or bits is None:
        fail("staging spec incomplete: cn=%r bits=%r" % (cn, bits))
    else:
        validate_staged(IDENTITY, cn, bits, "visible")

    # --- hidden cases: EXECUTE the deliverable on unseen inputs ---
    if not os.path.isdir(HIDDEN):
        fail("no hidden cases directory")
        return 1
    tmp = tempfile.mkdtemp(prefix="kiln_cipher_hidden_")
    try:
        cases = sorted(os.listdir(HIDDEN))
        if not cases:
            fail("no hidden cases present")
        for name in cases:
            case_path = os.path.join(HIDDEN, name, "case.json")
            if not os.path.isfile(case_path):
                fail("hidden case '%s' malformed (no case.json)" % name)
                continue
            try:
                with open(case_path, "r", encoding="utf-8") as fh:
                    case = json.load(fh)
                cn = str(case["cn"])
                bits = int(case["bits"])
            except Exception as exc:
                fail("hidden case '%s' unreadable: %s" % (name, exc))
                continue
            out_dir = os.path.join(tmp, name, "fresh", "nested")  # must be created
            r = subprocess.run(
                [sys.executable, MKCERT, "--cn", cn, "--bits", str(bits),
                 "--out-dir", out_dir],
                capture_output=True, text=True, timeout=240)
            if r.returncode != 0:
                fail("hidden case '%s': mkcert.py failed rc=%d %s"
                     % (name, r.returncode, r.stderr[-300:]))
                continue
            validate_staged(out_dir, cn, bits, "hidden:%s" % name)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print("verify failures:", failures)
        return 1
    print("kiln-cipher verify OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
