#!/usr/bin/env python3
"""Verifier for juniper-yonder.

Runs /app/attack.py on the shipped visible workspace and on every hidden
scenario under /tests/hidden, and checks every deliverable:

  * /app/keys               - recovered reduced-cipher low-bit round keys
                              (k0,k1) must match the scenario's true keys
  * /app/plaintexts.txt     - every ciphertext decrypted, one plaintext / line
                              (exact match, coverage = all ciphertexts)
  * /app/name.txt           - the isolated secret word, expected normalization
  * /app/attack.py          - runnable; its recover_key() must recover the key
                              from an encrypt callback oracle (hidden oracle)
  * decoded names           - base64-obfuscated filenames decoded correctly
  * crypto CLI coverage     - every file in src/ encrypted into encsrc/ and
                              each decrypts back to the original source bytes
                              with the recovered passcode

Writes reward to /logs/verifier/reward.txt (1 = all pass, 0 = otherwise).
"""
import os, sys, json, shutil, subprocess, importlib.util

APP = "/app/attack.py"
WS  = "/app/workspace"
failures = []

def fail(m):
    failures.append(m)

def run_attack(inc, out):
    shutil.rmtree(out, ignore_errors=True)
    return subprocess.run(["python3", APP, inc, out], capture_output=True, text=True)

def load_attack():
    spec = importlib.util.spec_from_file_location("attackmod", APP)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def oracle_binary(path):
    def o(p):
        r = subprocess.run([path], input="%04x\n" % p, capture_output=True, text=True, check=True)
        return int(r.stdout.strip(), 16)
    return o

def openssl_dec(cipher, passcode, outfile):
    subprocess.run(["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
                    "-pass", "pass:" + passcode, "-in", cipher, "-out", outfile],
                   check=True, capture_output=True)

def check_encsrc(inc, out, exp, label, passcode_fallback=None):
    srcdir = os.path.join(inc, "src")
    src_files = exp["src_files"]
    # full set coverage: nothing skipped, nothing extraneous
    out_files = []
    encroot = os.path.join(out, "encsrc")
    if os.path.isdir(encroot):
        for root, _, fs in os.walk(encroot):
            for fn in fs:
                out_files.append(os.path.relpath(os.path.join(root, fn), encroot))
    out_files = sorted(out_files)
    if out_files != sorted(src_files):
        fail("%s: encsrc file set %r != expected %r" % (label, out_files, src_files))
        return
    passcode = exp.get("passcode") or passcode_fallback
    for rel in src_files:
        cipher = os.path.join(encroot, rel)
        if not os.path.exists(cipher):
            fail("%s: missing encsrc/%s" % (label, rel)); continue
        try:
            openssl_dec(cipher, passcode, "/tmp/dec.bin")
            orig = open(os.path.join(srcdir, rel), "rb").read()
            got = open("/tmp/dec.bin", "rb").read()
        except Exception as e:
            fail("%s: decrypt/reopen error for %s: %s" % (label, rel, e)); continue
        if got != orig:
            fail("%s: encsrc/%s bytes differ from source" % (label, rel))

def check_scenario(inc, out, exp, label, need_module=True):
    r = run_attack(inc, out)
    if r.returncode != 0:
        fail("%s: attack.py runtime error: %s" % (label, r.stderr[-300:])); return
    # keys
    kp = os.path.join(out, "keys")
    if not os.path.exists(kp):
        fail("%s: no keys file" % label); return
    key_hex = None
    for ln in open(kp):
        if ln.startswith("key="):
            key_hex = ln.strip().split("=", 1)[1]
    if key_hex != exp["key_hex"]:
        fail("%s: recovered key %r != %r" % (label, key_hex, exp["key_hex"]))
    # plaintexts (exact, per line, full coverage)
    pp = os.path.join(out, "plaintexts.txt")
    if not os.path.exists(pp):
        fail("%s: no plaintexts.txt" % label)
    else:
        got = open(pp).read().splitlines()
        want = exp["plaintext_lines"]
        if got != want:
            fail("%s: plaintext lines %r != %r" % (label, got, want))
    # name normalization
    np_ = os.path.join(out, "name.txt")
    if not os.path.exists(np_):
        fail("%s: no name.txt" % label)
    else:
        nm = open(np_).read().strip().lower()
        want = exp["secret"].strip().lower()
        if nm != want:
            fail("%s: name.txt normalized %r != %r" % (label, nm, want))
    # decoded base64 filenames
    dn = os.path.join(out, "decoded_names.txt")
    if os.path.exists(dn):
        got = [l for l in open(dn).read().splitlines() if l != ""]
    else:
        got = []
    if got != exp["decoded"]:
        fail("%s: decoded names %r != %r" % (label, got, exp["decoded"]))
    # crypto CLI coverage over source tree
    check_encsrc(inc, out, exp, label)
    # module-level chosen-plaintext key recovery against the scenario's oracle
    if need_module and os.path.exists(APP):
        try:
            m = load_attack()
            o = oracle_binary(os.path.join(inc, "yonder_enc"))
            k0, k1 = m.recover_key(o)
        except Exception as e:
            fail("%s: recover_key module error: %s" % (label, e)); return
        if (k0, k1) != (exp["k0"], exp["k1"]):
            fail("%s: recover_key returned (%s,%s) != (%s,%s)" % (label, k0, k1, exp["k0"], exp["k1"]))

def main():
    # ---- visible: re-run on shipped workspace and check the deliverables ----
    vis_exp = {}
    if os.path.exists("/tests/expected.json"):
        vis_exp = json.load(open("/tests/expected.json"))
    if os.path.isdir(WS):
        check_scenario(WS, "/tmp/visout", vis_exp, "visible")
        # /app deliverables must match a fresh run (were actually produced)
        for f in ("keys", "plaintexts.txt", "name.txt"):
            a = os.path.join("/app", f); b = os.path.join("/tmp/visout", f)
            if not os.path.exists(a):
                fail("deliverable missing: /app/" + f)
            elif open(a).read() != open(b).read():
                fail("deliverable /app/%s differs from a correct run" % f)
        if not os.path.exists(APP):
            fail("deliverable missing: /app/attack.py")

    # ---- hidden cases ----
    hroot = "/tests/hidden"
    if os.path.isdir(hroot):
        cases = sorted(os.listdir(hroot))
        if len(cases) < 2:
            fail("expected >= 2 hidden cases")
        for c in cases:
            exp_path = os.path.join(hroot, c, "expected.json")
            if os.path.isdir(os.path.join(hroot, c)) and os.path.exists(exp_path):
                exp = json.load(open(exp_path))
                check_scenario(os.path.join(hroot, c), "/tmp/out_" + c, exp, "hidden:" + c)
            else:
                fail("hidden %s missing expected.json" % c)

    if failures:
        print("FAILURES:")
        for m in failures:
            print("  - " + m)
        open("/logs/verifier/reward.txt", "w").write("0")
        sys.exit(0)
    open("/logs/verifier/reward.txt", "w").write("1")
    print("ALL PASS")
    sys.exit(0)

if __name__ == "__main__":
    main()
