#!/bin/bash
# Blue Comet verifier — executes the delivered codec on visible + hidden cases.
mkdir -p /logs/verifier

python3 - <<'PY'
import importlib.util, os, glob, tempfile

DELIV = "/app/codec.py"
failures = []

def fail(msg):
    failures.append(msg)
    print("FAIL:", msg)

def load_codec():
    if not os.path.exists(DELIV):
        fail("deliverable missing: " + DELIV)
        return None
    try:
        spec = importlib.util.spec_from_file_location("codec", DELIV)
        codec = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(codec)
        assert callable(getattr(codec, "encode", None)) and callable(getattr(codec, "decode", None)), \
            "encode/decode missing"
        return codec
    except Exception as e:
        fail("could not import deliverable: " + repr(e))
        return None

def check(codec):
    try:
        tmp = tempfile.mkdtemp()

        # 1) visible case: round-trip /app/sample.txt
        src = "/app/sample.txt"
        if not os.path.exists(src):
            fail("visible input /app/sample.txt missing")
        else:
            enc = os.path.join(tmp, "v.enc"); dec = os.path.join(tmp, "v.dec")
            codec.encode(src, enc); codec.decode(enc, dec)
            if open(dec, "rb").read() != open(src, "rb").read():
                fail("visible round-trip")

        # 2) hidden raw round-trips (generality on fresh data)
        for src in glob.glob("/tests/hidden/raw/*"):
            enc = os.path.join(tmp, "h.enc"); dec = os.path.join(tmp, "h.dec")
            codec.encode(src, enc); codec.decode(enc, dec)
            if open(dec, "rb").read() != open(src, "rb").read():
                fail("hidden raw round-trip: " + os.path.basename(src))

        # 3) hidden valid encoded streams -> fixed expected bytes
        for src in glob.glob("/tests/hidden/valid_encoded/*"):
            base = os.path.basename(src)
            exp = "/tests/hidden/valid_expected/" + base
            dec = os.path.join(tmp, "vv.dec")
            codec.decode(src, dec)
            if open(dec, "rb").read() != open(exp, "rb").read():
                fail("hidden valid decode: " + base)

        # 4) hidden malformed streams must be rejected (raise, no output)
        for src in glob.glob("/tests/hidden/malformed/*"):
            dec = os.path.join(tmp, "m.dec")
            try:
                codec.decode(src, dec)
            except Exception:
                pass
            else:
                fail("malformed not rejected: " + os.path.basename(src))
    except Exception as e:
        fail("verifier error: " + repr(e))

codec = load_codec()
if codec is not None:
    check(codec)

with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not failures else "0")
PY