#!/usr/bin/env python3
"""Verifier for garnet-drift.

Validates the visible deliverables (/app/pki/bundle.pem built from the
provided edge pair, provenance JSON) and executes the deliverable
/app/mkbundle.py on freshly generated hidden key/cert scenarios:

  H1  fresh PKCS#8 RSA key + matching self-signed cert   -> must bundle
  H2  fresh EC key + matching self-signed cert           -> must bundle
  H4  the H1 pair wrapped in stray text + CRLF endings   -> must bundle
  H3  mismatched pair (key A, cert B)                    -> must refuse

Every expected value is recomputed here with openssl; nothing is copied from
the oracle. All parses are guarded; any failure -> reward 0.
"""
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile

APP = "/app"
TOOL = os.path.join(APP, "mkbundle.py")
BUNDLE = os.path.join(APP, "pki", "bundle.pem")
META = os.path.join(APP, "pki", "bundle.meta.json")
EDGE_KEY = os.path.join(APP, "pki", "edge.key")
EDGE_CRT = os.path.join(APP, "pki", "edge.crt")

KEY_HEADERS = {"PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY",
               "ENCRYPTED PRIVATE KEY", "DSA PRIVATE KEY"}

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg, flush=True)


def sh(args, data=None, timeout=60):
    return subprocess.run(args, input=data, capture_output=True,
                          timeout=timeout)


def openssl(args, data=None, timeout=60):
    """Run the openssl CLI; return (rc, stdout_bytes, stderr_bytes)."""
    try:
        r = sh(["openssl"] + args, data, timeout)
        return r.returncode, r.stdout, r.stderr
    except Exception as exc:
        return 99, b"", str(exc).encode()


def pem_blocks(text):
    """Return [(type, [lines])] for every PEM block in text. Guarded."""
    blocks = []
    cur = None
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        if cur is None:
            m = re.match(r"-----BEGIN ([A-Z0-9 ]+)-----\s*$", line)
            if m:
                cur = [m.group(1), []]
        else:
            if re.match(r"-----END %s-----\s*$" % re.escape(cur[0]), line):
                blocks.append((cur[0], cur[1]))
                cur = None
            else:
                cur[1].append(line)
    return blocks


def armor(kind, lines):
    body = "\n".join(l.strip() for l in lines if l.strip())
    return ("-----BEGIN %s-----\n%s\n-----END %s-----\n"
            % (kind, body, kind)).encode()


def pub_der_sha(kind, lines):
    """sha256 of the DER public key of a PEM block, via the openssl CLI.

    Normalizes through SPKI so PKCS#8/traditional/EC keys compare equal to
    their certificate's SubjectPublicKeyInfo. Returns None on any failure.
    """
    data = armor(kind, lines)
    if kind == "CERTIFICATE":
        rc, out, _ = openssl(["x509", "-pubkey", "-noout"], data)
        if rc != 0:
            return None
        rc2, out2, _ = openssl(["pkey", "-pubin", "-outform", "DER"], out)
        return hashlib.sha256(out2).hexdigest() if rc2 == 0 else None
    rc, out, _ = openssl(["pkey", "-pubout"], data)
    if rc != 0:
        return None
    rc2, out2, _ = openssl(["pkey", "-pubin", "-outform", "DER"], out)
    return hashlib.sha256(out2).hexdigest() if rc2 == 0 else None


def check_bundle(path, ctx, expect_cert_lines=None):
    """Validate a combined PEM bundle: parse, order, match, mode.

    Returns (ok, cert_lines) so callers can compare against a reference cert.
    """
    try:
        st = os.stat(path)
    except OSError as exc:
        fail("%s: missing bundle: %s" % (ctx, exc))
        return False, None
    mode = stat.S_IMODE(st.st_mode)
    if mode != 0o600:
        fail("%s: bundle mode is %o, want 600" % (ctx, mode))
        return False, None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            blocks = pem_blocks(fh.read())
    except Exception as exc:
        fail("%s: unreadable: %s" % (ctx, exc))
        return False, None
    if len(blocks) != 2:
        fail("%s: expected exactly 2 PEM blocks, found %d"
             % (ctx, len(blocks)))
        return False, None
    (ktype, klines), (ctype, clines) = blocks[0], blocks[1]
    if ktype not in KEY_HEADERS:
        fail("%s: first block is %r, not a private key" % (ctx, ktype))
        return False, None
    if ctype != "CERTIFICATE":
        fail("%s: second block is %r, not CERTIFICATE" % (ctx, ctype))
        return False, None
    # both blocks must parse independently via openssl
    if openssl(["pkey", "-noout"], armor(ktype, klines))[0] != 0:
        fail("%s: private-key block does not parse" % ctx)
        return False, None
    if openssl(["x509", "-noout"], armor(ctype, clines))[0] != 0:
        fail("%s: certificate block does not parse" % ctx)
        return False, None
    ksha = pub_der_sha(ktype, klines)
    csha = pub_der_sha(ctype, clines)
    if ksha is None or csha is None:
        fail("%s: could not extract public keys" % ctx)
        return False, None
    if ksha != csha:
        fail("%s: bundled key does not match bundled certificate" % ctx)
        return False, None
    if expect_cert_lines is not None:
        want = [l.strip() for l in expect_cert_lines if l.strip()]
        got = [l.strip() for l in clines if l.strip()]
        if got != want:
            fail("%s: bundle certificate differs from the requested cert"
                 % ctx)
            return False, None
    return True, clines


def run_tool(key, cert, out):
    """Execute the deliverable tool; returns (rc, out_exists)."""
    try:
        r = sh([sys.executable, TOOL, key, cert, out], timeout=90)
        rc = r.returncode
    except Exception:
        rc = None
    return rc, os.path.exists(out)


def gen_pair(kind, subj):
    """Generate a fresh key + self-signed cert; return (key_path, cert_path)."""
    d = tempfile.mkdtemp(prefix="garnet_h_")
    key = os.path.join(d, "key.pem")
    cert = os.path.join(d, "cert.pem")
    if kind == "rsa":
        rc, _, err = openssl(["genpkey", "-algorithm", "RSA",
                              "-pkeyopt", "rsa_keygen_bits:2048", "-out", key])
    elif kind == "ec":
        rc, _, err = openssl(["ecparam", "-name", "prime256v1", "-genkey",
                              "-noout", "-out", key])
    else:
        raise ValueError(kind)
    if rc != 0:
        raise RuntimeError("keygen failed: %s" % err.decode())
    rc, _, err = openssl(["req", "-new", "-x509", "-key", key, "-sha256",
                          "-subj", subj, "-days", "30", "-out", cert])
    if rc != 0:
        raise RuntimeError("self-sign failed: %s" % err.decode())
    return key, cert


def cert_lines_of(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return cert_lines_from_text(fh.read())


def cert_lines_from_text(text):
    for btype, lines in pem_blocks(text):
        if btype == "CERTIFICATE":
            return lines
    return None


def main():
    # ---------- visible deliverables ----------
    if not os.path.isfile(TOOL):
        fail("missing /app/mkbundle.py")
        print("verify failures:", failures)
        return 1

    try:
        edge_cert_lines = cert_lines_of(EDGE_CRT)
        if edge_cert_lines is None:
            fail("provided edge.crt contains no CERTIFICATE block")
    except Exception as exc:
        fail("cannot parse provided edge.crt: %s" % exc)
        edge_cert_lines = None

    ok, _ = check_bundle(BUNDLE, "visible /app/pki/bundle.pem",
                         expect_cert_lines=edge_cert_lines)
    if not ok:
        failures.append("visible bundle invalid")

    try:
        with open(META) as fh:
            meta = json.load(fh)
        assert isinstance(meta, dict), "meta not a dict"
        assert set(meta.keys()) == {"key_file", "cert_file",
                                    "key_sha256", "cert_sha256"}, meta.keys()
        assert meta["key_file"] == EDGE_KEY, meta["key_file"]
        assert meta["cert_file"] == EDGE_CRT, meta["cert_file"]
        with open(EDGE_KEY, "rb") as fh:
            want_k = hashlib.sha256(fh.read()).hexdigest()
        with open(EDGE_CRT, "rb") as fh:
            want_c = hashlib.sha256(fh.read()).hexdigest()
        assert meta["key_sha256"] == want_k, "key_sha256 mismatch (wrong key?)"
        assert meta["cert_sha256"] == want_c, "cert_sha256 mismatch"
    except AssertionError as exc:
        fail("visible /app/pki/bundle.meta.json: %s" % exc)
    except Exception as exc:
        fail("visible /app/pki/bundle.meta.json unreadable: %s" % exc)

    # ---------- hidden cases ----------
    tmp = tempfile.mkdtemp(prefix="garnet_verify_")

    h1_key = h1_cert = h2_key = h2_cert = None

    # H1: fresh PKCS#8 RSA pair
    try:
        h1_key, h1_cert = gen_pair("rsa", "/CN=h1.garnetdrift.test")
        out1 = os.path.join(tmp, "h1_bundle.pem")
        rc, exists = run_tool(h1_key, h1_cert, out1)
        if rc != 0 or not exists:
            fail("H1: mkbundle.py rc=%s exists=%s" % (rc, exists))
        else:
            ok, _ = check_bundle(out1, "H1 rsa")
            if not ok:
                failures.append("H1 bundle invalid")
            else:
                print("H1: ok")
    except Exception as exc:
        fail("H1 setup failed: %s" % exc)

    # H2: fresh EC pair
    try:
        h2_key, h2_cert = gen_pair("ec", "/CN=h2.garnetdrift.test")
        out2 = os.path.join(tmp, "h2_bundle.pem")
        rc, exists = run_tool(h2_key, h2_cert, out2)
        if rc != 0 or not exists:
            fail("H2: mkbundle.py rc=%s exists=%s" % (rc, exists))
        else:
            ok, _ = check_bundle(out2, "H2 ec")
            if not ok:
                failures.append("H2 bundle invalid")
            else:
                print("H2: ok")
    except Exception as exc:
        fail("H2 setup failed: %s" % exc)

    # H4: noisy inputs (stray text + CRLF) built from the H1 pair
    try:
        nk = os.path.join(tmp, "noisy_key.pem")
        nc = os.path.join(tmp, "noisy_cert.pem")
        with open(h1_key, "rb") as fh:
            kdata = fh.read()
        with open(h1_cert, "rb") as fh:
            cdata = fh.read()
        with open(nk, "wb") as fh:
            fh.write(b"# exported by fleet-tool v2\r\nrandom preamble line\n")
            fh.write(kdata.replace(b"\n", b"\r\n"))
            fh.write(b"\r\ntrailing junk\r\n")
        with open(nc, "wb") as fh:
            fh.write(b"Certificate request self-signature ok\r\n")
            fh.write(cdata.replace(b"\n", b"\r\n"))
        out4 = os.path.join(tmp, "h4_bundle.pem")
        rc, exists = run_tool(nk, nc, out4)
        if rc != 0 or not exists:
            fail("H4: mkbundle.py rc=%s exists=%s" % (rc, exists))
        else:
            ok, _ = check_bundle(out4, "H4 noisy")
            if not ok:
                failures.append("H4 bundle invalid")
            else:
                print("H4: ok")
    except Exception as exc:
        fail("H4 setup failed: %s" % exc)

    # H3: mismatched pair must be refused
    try:
        out3 = os.path.join(tmp, "h3_bundle.pem")
        if os.path.exists(out3):
            os.remove(out3)
        if h2_key is None or h1_cert is None:
            raise RuntimeError("prerequisite pair unavailable")
        rc, exists = run_tool(h2_key, h1_cert, out3)  # h2 key + h1 cert: mismatch
        if rc is None:
            fail("H3: mkbundle.py hung on mismatched pair")
        elif rc == 0 or exists:
            fail("H3: mkbundle.py accepted a mismatched pair (rc=%s "
                 "exists=%s)" % (rc, exists))
        else:
            print("H3: ok (mismatch refused)")
    except Exception as exc:
        fail("H3 setup failed: %s" % exc)

    print("verify failures:", failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
