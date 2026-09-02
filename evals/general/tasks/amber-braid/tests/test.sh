#!/bin/bash
# Verifier for amber-braid (executes-deliverable).
# Validates the visible deliverables (/app/bundle.pem + /app/manifest.txt
# against /app/provision/spec.env), then EXECUTES /app/mkbundle.py on every
# hidden spec under /tests/hidden and validates each produced bundle: PEM
# structure (key block first, cert block second), mode 0600, public keys equal,
# subject/key-type/size-or-curve/validity matching the spec, and manifest
# fingerprints matching recomputation. Writes reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

for f in /app/mkbundle.py /app/bundle.pem /app/manifest.txt; do
    test -f "$f" || { echo "missing $f" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }
done

python3 - <<'PY'
import hashlib, os, re, shutil, subprocess, sys, tempfile, time

TOOL = "/app/mkbundle.py"
VIS_SPEC = "/app/provision/spec.env"
VIS_BUNDLE = "/app/bundle.pem"
VIS_MANIFEST = "/app/manifest.txt"
HIDDEN = "/tests/hidden"

failures = []
def fail(m):
    failures.append(m)
    print("FAIL:", m, flush=True)

def run(cmd, timeout=60):
    return subprocess.run(cmd, capture_output=True, timeout=timeout)

def openssl(args, timeout=60):
    r = run(["openssl"] + args, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError("openssl %s failed: %s"
                           % (" ".join(args), r.stderr.decode("utf-8", "replace")[:300]))
    return r.stdout

def parse_spec(path):
    spec = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition("=")
            spec[k.strip()] = v.strip()
    return spec

def parse_manifest(path):
    out = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out

def extract_blocks(pem_text):
    """Return (key_block_text, cert_block_text) or raise; enforces order."""
    kb, ke = "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"
    cb, ce = "-----BEGIN CERTIFICATE-----", "-----END CERTIFICATE-----"
    ki = pem_text.index(kb)
    k_end = pem_text.index(ke, ki) + len(ke)
    ci = pem_text.index(cb)
    c_end = pem_text.index(ce, ci) + len(ce)
    if not (ki < ci):
        raise ValueError("private key block must come before certificate block")
    return pem_text[ki:k_end], pem_text[ci:c_end]

def check_bundle(bundle_path, manifest_path, spec, label):
    try:
        st = os.stat(bundle_path)
        if (st.st_mode & 0o777) != 0o600:
            fail("%s: bundle mode %o != 0600" % (label, st.st_mode & 0o777))
    except OSError as e:
        fail("%s: bundle stat error %r" % (label, e)); return
    try:
        pem = open(bundle_path, "r").read()
        keyblock, certblock = extract_blocks(pem)
    except Exception as e:
        fail("%s: bundle PEM parse/order error %r" % (label, e)); return
    try:
        with tempfile.TemporaryDirectory() as td:
            kp = os.path.join(td, "k.pem"); cp = os.path.join(td, "c.pem")
            open(kp, "w").write(keyblock); open(cp, "w").write(certblock)
            # public keys must match
            kpub = openssl(["pkey", "-in", kp, "-pubout", "-outform", "DER"])
            cpub_pem = openssl(["x509", "-in", cp, "-pubkey", "-noout"])
            p = subprocess.Popen(["openssl", "pkey", "-pubin", "-outform", "DER"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE)
            cpub, cerr = p.communicate(cpub_pem, timeout=60)
            if p.returncode != 0:
                raise RuntimeError("cert pubkey extract failed: %r" % cerr[:200])
            if hashlib.sha256(kpub).hexdigest() != hashlib.sha256(cpub).hexdigest():
                fail("%s: certificate public key != private key public key" % label)
            # manifest fingerprints
            man = parse_manifest(manifest_path)
            cert_der = openssl(["x509", "-in", cp, "-outform", "DER"])
            want_cert = hashlib.sha256(cert_der).hexdigest()
            want_pub = hashlib.sha256(kpub).hexdigest()
            if man.get("cert_fingerprint_sha256") != want_cert:
                fail("%s: manifest cert fingerprint %r != %r"
                     % (label, man.get("cert_fingerprint_sha256"), want_cert))
            if man.get("pubkey_fingerprint_sha256") != want_pub:
                fail("%s: manifest pubkey fingerprint %r != %r"
                     % (label, man.get("pubkey_fingerprint_sha256"), want_pub))
            if len(man) != 2:
                fail("%s: manifest must have exactly 2 lines, got %d" % (label, len(man)))
            # key type / size / curve
            txt = openssl(["pkey", "-in", kp, "-text", "-noout"]).decode("utf-8", "replace")
            ktype = spec["key_type"].upper()
            if ktype == "RSA":
                if "Private-Key" not in txt:
                    fail("%s: key is not RSA" % label)
                else:
                    m = re.search(r"Private-Key:\s*\((\d+) bit", txt)
                    if not m or int(m.group(1)) != int(spec["key_bits"]):
                        fail("%s: RSA bits %r != %s"
                             % (label, m.group(1) if m else "?", spec["key_bits"]))
            else:
                if ("ASN1 OID: %s" % spec["curve"]) not in txt:
                    fail("%s: EC curve mismatch (want %s)" % (label, spec["curve"]))
            # subject
            subj = openssl(["x509", "-in", cp, "-noout", "-subject",
                            "-nameopt", "RFC2253"]).decode()
            comps = dict(re.findall(r"(?:^|[,=])\s*(CN|O|C)=([^,]*)", subj.strip()))
            for key, speckey in (("CN", "common_name"), ("O", "organization"), ("C", "country")):
                if comps.get(key) != spec[speckey]:
                    fail("%s: subject %s=%r != spec %r"
                         % (label, key, comps.get(key), spec[speckey]))
            # validity span
            dates = openssl(["x509", "-in", cp, "-noout", "-startdate", "-enddate"]).decode()
            vals = {}
            for ln in dates.splitlines():
                k, _, v = ln.partition("=")
                vals[k.strip()] = " ".join(v.split())
            import calendar
            fmt = "%b %d %H:%M:%S %Y %Z"
            t0 = time.strptime(vals["notBefore"], fmt)
            t1 = time.strptime(vals["notAfter"], fmt)
            span = (calendar.timegm(t1) - calendar.timegm(t0)) / 86400.0
            want = int(spec["validity_days"])
            if abs(span - want) > 1.0:
                fail("%s: validity span %.1f days != %d" % (label, span, want))
    except Exception as e:
        fail("%s: bundle validation error %r" % (label, e))

# ---- visible deliverables ----
vis = parse_spec(VIS_SPEC)
check_bundle(VIS_BUNDLE, VIS_MANIFEST, vis, "visible")

# ---- hidden cases: EXECUTE the deliverable tool on unseen specs ----
cases = sorted(d for d in os.listdir(HIDDEN)
               if os.path.isdir(os.path.join(HIDDEN, d))) if os.path.isdir(HIDDEN) else []
if len(cases) < 2:
    fail("expected >= 2 hidden cases, found %d" % len(cases))
for case in cases:
    spec_path = os.path.join(HIDDEN, case, "spec.env")
    if not os.path.isfile(spec_path):
        fail("hidden '%s': missing spec.env" % case); continue
    outdir = tempfile.mkdtemp(prefix="ab_%s_" % case)
    bundle = os.path.join(outdir, "bundle.pem")
    manifest = os.path.join(outdir, "manifest.txt")
    try:
        r = run([sys.executable, TOOL, spec_path, bundle, manifest], timeout=120)
        if r.returncode != 0:
            fail("hidden '%s': mkbundle.py exited %d: %s"
                 % (case, r.returncode, r.stderr[-300:])); continue
        if not (os.path.isfile(bundle) and os.path.isfile(manifest)):
            fail("hidden '%s': outputs missing" % case); continue
        check_bundle(bundle, manifest, parse_spec(spec_path), "hidden:" + case)
    except subprocess.TimeoutExpired:
        fail("hidden '%s': mkbundle.py timed out" % case)

print("verify failures:", failures)
if failures:
    open("/logs/verifier/reward.txt", "w").write("0")
else:
    open("/logs/verifier/reward.txt", "w").write("1")
PY
exit 0
