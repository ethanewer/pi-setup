#!/usr/bin/env bash
# quartz-orchid verifier. Runs after (positive) or without (negative) solve.sh.
# Writes 1 (all gates pass) or 0 to /logs/verifier/reward.txt.

mkdir -p /logs/verifier
REWARD=1
fail(){ echo "FAIL: $1" >&2; REWARD=0; }

FALLBACK=1630454400
FRESH=1728000000

echo "[gate] tar (visible fallback epoch)"
if [ -f /app/reproduce.tar ]; then
  python3 - /app/reproduce.tar "$FALLBACK" <<'PY'
import sys, tarfile
tarfile_path, epoch = sys.argv[1], int(sys.argv[2])
t = tarfile.open(tarfile_path)
m = {x.name: x for x in t.getmembers()}
names = set(m)
req = {"bin/a.txt", "bin/alias.txt", "links/guide-link.txt",
       "docs/guide.txt",
       "deep/level0/level1/level2/level3/level4/level5/level6/level7/leaf.txt"}
missing = req - names
if missing:
    sys.exit("missing members: %s" % sorted(missing))
assert m["bin/alias.txt"].issym(), "alias.txt not kept as symlink"
assert m["links/guide-link.txt"].issym(), "guide-link not kept as symlink"
bad = [n for n in names if m[n].mtime != epoch]
if bad:
    sys.exit("members with wrong mtime (expected %d): %s" % (epoch, bad[:8]))
if not any(len(n) > 100 for n in names):
    sys.exit("no long (>100) member name present")
if not any(n.count("/") >= 8 for n in names):
    sys.exit("no deeply nested (>8 levels) member present")
if any(n.startswith("./") for n in names):
    sys.exit("member names must not carry a leading './'")
print("ok: %d members, symmetric links intact, mtimes==epoch, long/deep present" % len(names))
PY
else
  fail "/app/reproduce.tar missing"
fi

echo "[gate] tar (hidden source tree, fresh BUILD_EPOCH)"
if [ -x /app/mkarchive.sh ]; then
  rm -rf /tmp/qh && mkdir -p /tmp/qh
  out=/tmp/qh/out.tar
  BUILD_EPOCH="$FRESH" /app/mkarchive.sh /tests/hidden/archive/src "$out"
  if [ -f "$out" ]; then
    python3 - "$out" "$FRESH" <<'PY'
import sys, tarfile
tpath, epoch = sys.argv[1], int(sys.argv[2])
t = tarfile.open(tpath)
m = {x.name: x for x in t.getmembers()}
names = set(m)
need = {"bin/primary.dat", "bin/backup.dat", "links/shortcut.txt", "docs/note.txt"}
if need - names:
    sys.exit("hidden tar missing members: %s" % sorted(need - names))
assert m["bin/backup.dat"].issym(), "hidden backup.dat not a symlink"
assert m["links/shortcut.txt"].issym(), "hidden shortcut not a symlink"
badm = [n for n in names if m[n].mtime != epoch]
if badm:
    sys.exit("hidden mtimes wrong: %s" % badm[:8])
assert any(len(n) > 100 for n in names), "hidden tar lacks long name"
assert any(n.count("/") >= 9 for n in names), "hidden tar lacks deep member"
print("OK: hidden tar keeps symlinks, fresh epoch, long/deep names")
PY
  else
    fail "mkarchive.sh produced no tar for hidden src"
  fi
else
  fail "/app/mkarchive.sh missing/not executable"
fi

echo "[gate] split.py (hidden round trips + edge cases)"
if [ -x /app/split.py ]; then
  python3 - <<'PY'
import os, shutil, subprocess, sys, tempfile, json

SPLIT = "/app/split.py"
HIDDEN = "/tests/hidden/split"

def run(args, **kw):
    return subprocess.run([sys.executable, SPLIT] + args,
                          capture_output=True, text=True, **kw)

def roundtrip(path, cap):
    d = tempfile.mkdtemp(prefix="qsp_")
    out = os.path.join(tempfile.gettempdir(), "qsp_join_" + os.path.basename(path))
    try:
        r = run(["split", path, str(cap), d])
        if r.returncode != 0:
            return f"split failed (rc={r.returncode}): {r.stderr.strip()}"
        size = os.path.getsize(path)
        k = (size + cap - 1) // cap if size else 0
        mpath = os.path.join(d, "manifest.json")
        m = json.load(open(mpath))
        if (m["size"], m["cap"], m["chunks"]) != (size, cap, k):
            return "manifest mismatch: " + str(m)
        # verify every chunk is at most cap bytes
        for i in range(k):
            cp = os.path.join(d, "chunk_%06d" % i)
            if os.path.getsize(cp) > cap:
                return f"chunk {i} exceeds cap"
        # reassemble
        rj = run(["join", d, out])
        if rj.returncode != 0:
            return "join failed: " + rj.stderr.strip()
        with open(out, "rb") as fh:
            rejoined = fh.read()
        with open(path, "rb") as fh:
            orig = fh.read()
        if rejoined != orig:
            return "round trip bytes differ"
        return None
    finally:
        shutil.rmtree(d, ignore_errors=True)
        if os.path.exists(out):
            os.remove(out)

cases = [
    (os.path.join(HIDDEN, "oversized.bin"), 4096),
    (os.path.join(HIDDEN, "multiple.bin"), 128),
    (os.path.join(HIDDEN, "single.bin"), 10000),
    (os.path.join(HIDDEN, "empty.bin"), 4096),
    (os.path.join(HIDDEN, "oversized.bin"), 1),
]
for path, cap in cases:
    if not os.path.exists(path):
        sys.exit(f"missing hidden split input: {path}")
    err = roundtrip(path, cap)
    if err:
        sys.exit(f"split edge case cap={cap}: {err}")

# error handling gates
r = run(["split", "/does/not/exist", "10", "/tmp/qsp_nope"])
if r.returncode == 0 or "no such file" not in r.stderr:
    sys.exit("missing-input error case not handled")
d = tempfile.mkdtemp(prefix="qsp_bad_")
try:
    r = run(["split", os.path.join(HIDDEN, "oversized.bin"), "0", d])
    if r.returncode == 0 or os.path.exists(os.path.join(d, "manifest.json")):
        sys.exit("cap=0 not rejected")
finally:
    shutil.rmtree(d, ignore_errors=True)
print("OK: split round trips (multiple, exact-multiple, oversized~single, empty, cap=1) + error handling")
PY
  [ "$?" -eq 0 ] || fail "split hidden/edge gate failed"
else
  fail "/app/split.py missing/not executable"
fi

echo "[gate] extract.txt from encrypted 7z"
if [ -f /app/extract.txt ]; then
  PW="$(cat /app/credentials/key.txt)"
  ref_tmp=/tmp/ref_member.txt
  if 7z x -bd -y -p"$PW" -so /app/vault.7z payload_secret.txt > "$ref_tmp" 2>/dev/null \
     && cmp -s "$ref_tmp" /app/extract.txt; then
    echo "OK: extract.txt matches decrypted member"
  else
    fail "/app/extract.txt does not match decrypted vault member"
  fi
else
  fail "/app/extract.txt missing"
fi

echo "[gate] digests (visible + hidden, recomputed independently)"
if [ -x /app/digester.py ]; then
  python3 - <<'PY' || fail "digest comparison failed"
import hashlib, os, subprocess, sys
SALT = "ff4c8e17b3013d38f6a9c71b0d21e44a"
ITER = 100000

def compute(treedir):
    out = []
    for root, _, files in os.walk(treedir):
        for name in sorted(files):
            p = os.path.join(root, name)
            if not os.path.isfile(p):
                continue
            data = open(p, "rb").read()
            dk = hashlib.pbkdf2_hmac("sha256", data, bytes.fromhex(SALT), ITER, dklen=32)
            rel = os.path.relpath(p, treedir).replace(os.sep, "/")
            out.append(rel + "\t" + dk.hex())
    out.sort()
    return "\n".join(out) + ("\n" if out else "")

# visible digests file must match independent recomputation
exp = compute("/app/tree")
got = open("/app/digests.txt").read()
assert got == exp, "visible digests.txt mismatch"

# hidden tree: digester.py must match independent recomputation
hidden_exp = compute("/tests/hidden/digests/tree")
sub = subprocess.run([sys.executable, "/app/digester.py", "/tests/hidden/digests/tree"],
                     capture_output=True, text=True)
assert sub.returncode == 0, "digester.py crashed on hidden tree"
assert sub.stdout == hidden_exp, "digester.py hidden output mismatch"
print("OK: digests.txt and digester hidden run match recomputation")
PY
else
  fail "/app/digester.py missing/not executable"
fi

echo "REWARD=$REWARD"
echo "$REWARD" > /logs/verifier/reward.txt
exit 0