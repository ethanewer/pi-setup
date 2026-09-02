#!/bin/bash
# Verifier for indigo-ember (executes-deliverable). Enforces the no-modify rule
# on /app/station, unit-tests the exported cryptogram/passcode helpers, EXECUTES
# /app/recover.py on the shipped scenario and on every hidden scenario, and
# byte-checks the deliverables /app/key.txt and /app/plaintexts.txt.
# Writes reward (1/0) to /logs/verifier/reward.txt. Never crashes on malformed
# agent output; every failure is collected, not raised.
set -u
mkdir -p /logs/verifier

PRISTINE_CIPHER_REF="1808c7440effc43924ff5051a30cc92bb3bc48478000675b88001c7439be3ce1"
PRISTINE_CIPHERTEXTS="27a360cb6ac1c77610363e25ee6ba615297c745fdb3aceb2b7e5bb920c968fbf"
PRISTINE_CLUE="7fdeff200b0195c74e603bb26d923a9acafc6b1c8077157df94df9266fec2356"
PRISTINE_CRYPTOGRAM="b393ef72f867a9965100e24fea12a145077dc72fdc83e4aa391d2489b13b90eb"
PRISTINE_KEYBOX="855ec454110325e578a87dd763e1ff94b5b47ada15f90556cb0879699006e300"

python3 - "$PRISTINE_CIPHER_REF" "$PRISTINE_CIPHERTEXTS" "$PRISTINE_CLUE" \
          "$PRISTINE_CRYPTOGRAM" "$PRISTINE_KEYBOX" <<'PY'
import hashlib, importlib.util, json, os, shutil, subprocess, sys, tempfile

HASHES = {
    "cipher_ref.py": sys.argv[1], "ciphertexts.txt": sys.argv[2],
    "clue.json": sys.argv[3], "cryptogram.txt": sys.argv[4],
    "keybox.enc": sys.argv[5],
}
TOOL = "/app/recover.py"
STATION = "/app/station"
failures = []

def fail(m):
    failures.append(m)
    print("FAIL:", m)

def sha(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None

# ---- no-modify on the shipped scenario -------------------------------------
for fn, want in HASHES.items():
    got = sha(os.path.join(STATION, fn))
    if got is None:
        fail("no-modify: /app/station/%s missing" % fn)
    elif got != want:
        fail("no-modify: /app/station/%s was modified" % fn)

# ---- load the deliverable tool ----------------------------------------------
mod = None
if not os.path.isfile(TOOL):
    fail("missing deliverable %s" % TOOL)
else:
    try:
        spec = importlib.util.spec_from_file_location("recover_mod", TOOL)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as e:
        fail("cannot import %s: %r" % (TOOL, e))
        mod = None

# ---- unit-check the exported helpers (synthetic edge cases) -----------------
if mod is not None:
    if not callable(getattr(mod, "decode_cryptogram", None)):
        fail("missing exported function decode_cryptogram")
    else:
        clue = {"kind": "operator-note",
                "plain_alphabet": "abcdefghijklmnopqrstuvwxyz",
                "cipher_alphabet": "qwertyuiopasdfghjklzxcvbnm"}
        # cipher_alphabet[i] encodes plain letter i
        def ref_decode(text):
            out = []
            for ch in text:
                low = ch.lower()
                if low.isalpha() and 'a' <= low <= 'z':
                    i = clue["cipher_alphabet"].index(low)
                    dec = clue["plain_alphabet"][i]
                    out.append(dec.upper() if ch.isupper() else dec)
                else:
                    out.append(ch)
            return "".join(out)
        samples = ["KYEE=NBQR-11TQ, ozhs", "Pass=Sable-42 END", "9 - _ ! xY",
                   "MIXED Case Zz"]
        for s in samples:
            try:
                got = mod.decode_cryptogram(s, clue)
            except Exception as e:
                fail("decode_cryptogram(%r) raised %r" % (s, e)); break
            if got != ref_decode(s):
                fail("decode_cryptogram(%r) = %r, want %r" % (s, got, ref_decode(s)))
                break
        else:
            print("decode_cryptogram OK")
    if not callable(getattr(mod, "extract_passcode", None)):
        fail("missing exported function extract_passcode")
    else:
        pc_cases = [("run PASS=abc-123", "abc-123"),
                    ("run PASS=abc-123, seal", "abc-123"),
                    ("note PASS=Grid-91X", "Grid-91X"),      # end, no punctuation
                    ("PASS=X9 then done", "X9"),
                    ("nothing here", ""),
                    ("empty PASS=", "")]
        for note, want in pc_cases:
            try:
                got = mod.extract_passcode(note)
            except Exception as e:
                fail("extract_passcode(%r) raised %r" % (note, e)); break
            if got != want:
                fail("extract_passcode(%r) = %r, want %r" % (note, got, want))
                break
        else:
            print("extract_passcode OK")

# ---- run the tool on a scenario dir and compare against expected ------------
def run_case(scen_dir, exp, label):
    out = tempfile.mkdtemp(prefix="ie_case_")
    if os.path.exists("/tmp/ie_out"):
        shutil.rmtree("/tmp/ie_out", ignore_errors=True)
    out = "/tmp/ie_out"
    r = subprocess.run(["python3", TOOL, scen_dir, out],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        fail("%s: recover.py exited %d (stderr: %s)"
             % (label, r.returncode, (r.stderr or "")[:300]))
        return
    # key.txt
    kp = os.path.join(out, "key.txt")
    if not os.path.isfile(kp):
        fail("%s: key.txt missing" % label)
    else:
        try:
            lines = [l.strip() for l in open(kp) if l.strip()]
            ok = (len(lines) == 1 and lines[0].startswith("key=")
                  and lines[0][4:] == "%04x" % exp["key"])
            if not ok:
                fail("%s: key.txt = %r, want key=%04x" % (label, lines, exp["key"]))
        except Exception as e:
            fail("%s: key.txt unreadable: %r" % (label, e))
    # plaintexts.txt: every block, one per line, exact order
    pp = os.path.join(out, "plaintexts.txt")
    if not os.path.isfile(pp):
        fail("%s: plaintexts.txt missing" % label)
    else:
        try:
            got = open(pp).read().split("\n")
            if got and got[-1] == "":
                got = got[:-1]
            if got != exp["plaintexts"]:
                fail("%s: plaintexts mismatch (got %d lines, want %d; first diff: %r)"
                     % (label, len(got), len(exp["plaintexts"]),
                        next((a for a, b in zip(got, exp["plaintexts"]) if a != b),
                             None)))
        except Exception as e:
            fail("%s: plaintexts.txt unreadable: %r" % (label, e))

if mod is not None:
    # visible scenario: tool run + the /app deliverables themselves
    vexp_path = "/tests/expected.json"
    try:
        vexp = json.load(open(vexp_path))
    except Exception as e:
        vexp = None
        fail("visible expected.json unreadable: %r" % e)
    if vexp is not None:
        run_case(STATION, vexp, "visible")
        for deliv, checker in (
            ("/app/key.txt", "key"), ("/app/plaintexts.txt", "plain")):
            if not os.path.isfile(deliv):
                fail("missing deliverable %s" % deliv)
        if os.path.isfile("/app/key.txt"):
            try:
                got = [l.strip() for l in open("/app/key.txt") if l.strip()]
                if not (len(got) == 1 and got[0] == "key=%04x" % vexp["key"]):
                    fail("/app/key.txt = %r, want key=%04x" % (got, vexp["key"]))
            except Exception as e:
                fail("/app/key.txt unreadable: %r" % e)
        if os.path.isfile("/app/plaintexts.txt"):
            try:
                got = open("/app/plaintexts.txt").read().split("\n")
                if got and got[-1] == "":
                    got = got[:-1]
                if got != vexp["plaintexts"]:
                    fail("/app/plaintexts.txt does not match the visible expected "
                         "(%d lines vs %d)" % (len(got), len(vexp["plaintexts"])))
            except Exception as e:
                fail("/app/plaintexts.txt unreadable: %r" % e)

    # ---- hidden scenarios ----------------------------------------------------
    hroot = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hroot)
                   if os.path.isdir(os.path.join(hroot, d))) if os.path.isdir(hroot) else []
    if len(cases) < 2:
        fail("expected >= 2 hidden scenarios, found %d" % len(cases))
    for name in cases:
        d = os.path.join(hroot, name)
        ep = os.path.join(d, "expected.json")
        need = ["cryptogram.txt", "clue.json", "keybox.enc", "ciphertexts.txt"]
        if not all(os.path.isfile(os.path.join(d, n)) for n in need) or not os.path.isfile(ep):
            fail("hidden '%s' incomplete" % name)
            continue
        try:
            exp = json.load(open(ep))
        except Exception as e:
            fail("hidden '%s' expected.json unreadable: %r" % (name, e))
            continue
        run_case(d, exp, "hidden:" + name)

print("failures:", len(failures))
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not failures else "0")
sys.exit(0)
PY
exit 0
