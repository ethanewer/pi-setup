#!/bin/bash
# Verifier for marble-hollow (executes-deliverable).
#
# Enforces the no-modify rule on /app/snapshots.blob, validates the visible
# deliverables (/app/segments/segments.json, /app/snapshots.restored), then
# EXECUTES the deliverable /app/segmenter.py on every hidden case (pack/merge
# round trips, quota/header checks, tamper rejection). Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible blob (the instruction tells the agent
# not to modify it; tampering would defeat the visible-case checks).
PRISTINE_BLOB_SHA="8cf625212fbe2bd96e15c062de86840be54fa181e030a481659db5585813afd5"

no_modify_broken=0
if [ ! -f /app/snapshots.blob ]; then
    echo "no-modify: /app/snapshots.blob missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/snapshots.blob | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_BLOB_SHA" ]; then
        echo "no-modify: /app/snapshots.blob was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import hashlib, json, os, re, shutil, subprocess, sys

SEG = "/app/segmenter.py"
HEADER_LEN = 83
no_modify_broken = int(sys.argv[1])
probs = []


def check(name, cond, detail=""):
    if not cond:
        probs.append("%s  <%s>" % (name, detail))


def run(args, timeout=60):
    return subprocess.run([sys.executable, SEG] + args,
                          capture_output=True, text=True, timeout=timeout)


def validate_pack(outdir, input_path, cap, size):
    """Structural validation of a pack directory; returns (ok, K)."""
    idx_path = os.path.join(outdir, "segments.json")
    if not os.path.isfile(idx_path):
        return False, None, "segments.json missing"
    try:
        with open(idx_path) as f:
            idx = json.load(f)
    except Exception as exc:
        return False, None, "segments.json unreadable: %s" % exc
    payload_cap = cap - HEADER_LEN
    k_want = (size + payload_cap - 1) // payload_cap if size else 0
    if (idx.get("format") != "SEG/1" or idx.get("size") != size
            or idx.get("cap") != cap or idx.get("segments") != k_want
            or idx.get("header_len") != HEADER_LEN):
        return False, k_want, "index fields wrong: %r" % idx
    with open(input_path, "rb") as f:
        data = f.read()
    if idx.get("digest") != hashlib.sha256(data).hexdigest():
        return False, k_want, "index digest wrong"
    if idx.get("input") != os.path.basename(input_path):
        return False, k_want, "index input basename wrong: %r" % idx.get("input")
    segs = sorted(n for n in os.listdir(outdir) if re.match(r"^seg_\d{6}\.bin$", n))
    if len(segs) != k_want:
        return False, k_want, "segment file count %d != %d" % (len(segs), k_want)
    for i in range(k_want):
        p = os.path.join(outdir, "seg_%06d.bin" % i)
        if not os.path.isfile(p):
            return False, k_want, "missing seg_%06d.bin" % i
        raw = open(p, "rb").read()
        if len(raw) > cap:
            return False, k_want, "segment %d exceeds cap (%d > %d)" % (i, len(raw), cap)
        header, payload = raw[:HEADER_LEN], raw[HEADER_LEN:]
        try:
            htxt = header.decode("ascii")
        except UnicodeDecodeError:
            return False, k_want, "segment %d header not ascii" % i
        if not re.match(r"^SEG\t%06d\t%06d\t[0-9a-f]{64}\n$" % (i, k_want), htxt):
            return False, k_want, "segment %d header mismatch: %r" % (i, htxt)
        if hashlib.sha256(payload).hexdigest() != htxt[:-1].split("\t")[3]:
            return False, k_want, "segment %d payload digest mismatch" % i
        want = data[i * payload_cap:(i + 1) * payload_cap]
        if payload != want:
            return False, k_want, "segment %d payload bytes wrong" % i
    return True, k_want, ""


failures = []
if no_modify_broken:
    failures.append("visible blob modified or missing (no-modify rule)")
probs.extend(failures)

# ---- deliverable /app/segmenter.py must exist ----
if not os.path.isfile(SEG):
    probs.append("segmenter_missing <%s>" % SEG)

# ---- visible deliverables: /app/segments/segments.json + /app/snapshots.restored
if os.path.isfile(SEG) and not no_modify_broken:
    if not os.path.isfile("/app/segments/segments.json"):
        probs.append("visible_index_missing </app/segments/segments.json>")
    else:
        ok, k, why = validate_pack("/app/segments", "/app/snapshots.blob", 65536, 200000)
        check("visible_pack_valid", ok, why)
    if not os.path.isfile("/app/snapshots.restored"):
        probs.append("visible_restore_missing </app/snapshots.restored>")
    else:
        a = open("/app/snapshots.blob", "rb").read()
        b = open("/app/snapshots.restored", "rb").read()
        check("visible_restore_bytes", a == b)

# ---- hidden cases: pack/merge round trips + error paths ----
hd = "/tests/hidden"
if os.path.isdir(hd) and os.path.isfile(SEG):
    cases = sorted(d for d in os.listdir(hd) if os.path.isdir(os.path.join(hd, d)))
    if not cases:
        probs.append("no hidden cases present")
    work = "/tmp/marble_hollow_work"
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    for c in cases:
        base = os.path.join(hd, c)
        inp, capp, exp = (os.path.join(base, "input.bin"),
                          os.path.join(base, "cap.txt"),
                          os.path.join(base, "expected.json"))
        if not all(os.path.isfile(p) for p in (inp, capp, exp)):
            probs.append("hidden '%s' malformed" % c)
            continue
        try:
            with open(exp) as f:
                expect = json.load(f).get("pack")
            cap = int(open(capp).read().strip())
            size = os.path.getsize(inp)
        except Exception as exc:
            probs.append("hidden '%s' fixtures unreadable <%s>" % (c, exc))
            continue

        outdir = os.path.join(work, c, "segs")
        r = run(["pack", inp, str(cap), outdir])
        if expect == "error":
            check("hidden '%s' pack_rejects" % c, r.returncode != 0, r.stdout[-200:])
            check("hidden '%s' pack_wrote_nothing" % c, not os.path.exists(outdir))
            continue
        if r.returncode != 0:
            probs.append("hidden '%s' pack_failed <%s>" % (c, (r.stderr or r.stdout)[-300:]))
            continue
        ok, k, why = validate_pack(outdir, inp, cap, size)
        check("hidden '%s' pack_valid" % c, ok, why)
        if not ok:
            continue

        # merge -> byte-exact round trip
        restored = os.path.join(work, c, "restored.bin")
        m = run(["merge", outdir, restored])
        check("hidden '%s' merge_exit0" % c, m.returncode == 0, (m.stderr or m.stdout)[-300:])
        if m.returncode == 0:
            check("hidden '%s' roundtrip" % c,
                  open(restored, "rb").read() == open(inp, "rb").read())

        # tamper: remove a segment -> merge must fail and write nothing
        if k >= 1:
            tdir = os.path.join(work, c, "tampered")
            shutil.copytree(outdir, tdir)
            os.remove(os.path.join(tdir, "seg_%06d.bin" % 0))
            tout = os.path.join(work, c, "tampered.out")
            m2 = run(["merge", tdir, tout])
            check("hidden '%s' tamper_missing_rejected" % c, m2.returncode != 0)
            check("hidden '%s' tamper_no_output" % c, not os.path.exists(tout))

        # tamper: flip a payload byte -> merge must fail
        if k >= 1:
            tdir2 = os.path.join(work, c, "tampered2")
            shutil.copytree(outdir, tdir2)
            p = os.path.join(tdir2, "seg_%06d.bin" % (k - 1))
            raw = bytearray(open(p, "rb").read())
            raw[-1] ^= 0x01
            open(p, "wb").write(bytes(raw))
            tout2 = os.path.join(work, c, "tampered2.out")
            m3 = run(["merge", tdir2, tout2])
            check("hidden '%s' tamper_flip_rejected" % c, m3.returncode != 0)
            check("hidden '%s' tamper_flip_no_output" % c, not os.path.exists(tout2))
else:
    if not os.path.isdir(hd):
        probs.append("hidden dir missing")

print("verify failures:", probs)
sys.exit(1 if probs else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
