#!/usr/bin/env bash
# kite-helix verifier (runs as root after the agent). Deliberately independent
# of the oracle's implementation: it recomputes every expectation from the
# fixture itself and compares against what /app/solve.py produced.
# Writes reward to /logs/verifier/reward.txt; must be 0 on a pristine image.
set -uo pipefail

REWDIR=/logs/verifier
mkdir -p "$REWDIR"
echo 0 > "$REWDIR/reward.txt"

if [ ! -x /app/solve.py ]; then
  echo "kite-helix: /app/solve.py missing or not executable" >&2
  echo 0 > "$REWDIR/reward.txt"
  exit 0
fi

cat > /tmp/kcheck.py <<'PYEOF'
import re, sys, os, json, gzip, hashlib, zipfile, tarfile, pathlib, subprocess
import posixpath

WS = pathlib.Path(sys.argv[1]).resolve()
DATA = WS / "data"
OUT = WS / "out"
AN = WS / "answer.json"
TARGET_MEMBER = "manifest/release/current/config.yaml"
EXCLUDE_ENDINGS = (".pyc", ".o", ".tmp", ".cache")
EXCLUDE_DIRS = ("vendor", "__pycache__")


def fail(msg):
    print("KCHECK_FAIL[%s]: %s" % (WS.name, msg))
    sys.exit(1)


def snapshot(root):
    out = {}
    for p in sorted(root.rglob("*")):
        if not (p.is_file() or p.is_symlink()):
            continue
        rel = p.relative_to(root).as_posix()
        try:
            out[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError:
            out[rel] = "UNREADABLE"
    return out


# ---- run the deliverable on this workspace (source must stay untouched) ----
before = snapshot(DATA)
r = subprocess.run([sys.executable, "/app/solve.py", str(WS)],
                   capture_output=True, text=True)
if r.returncode != 0:
    fail("solve.py exited %r: %s %s" % (r.returncode, r.stdout, r.stderr))
after = snapshot(DATA)
if before != after:
    diff = [k for k in before if before[k] != after.get(k)] or ["(added)"]
    fail("source data was modified (C-50c): %s" % diff[:5])

# ---- answer.json ----
if not AN.exists():
    fail("no answer.json")
ans = json.loads(AN.read_text())

# ---- competency: list archive members to surface the wanted token ----
with zipfile.ZipFile(DATA / "manifest" / "artifact.zip") as z:
    names = z.namelist()
    if TARGET_MEMBER not in names:
        fail("target member missing from fixture archive")
    cfg = z.read(TARGET_MEMBER).decode()
m = re.search(r"^\s*app_token\s*[:=]\s*[\"']?([^\s\"']+)", cfg, re.M)
exp_token = m.group(1)
if ans.get("token") != exp_token:
    fail("token mismatch: got %r want %r" % (ans.get("token"), exp_token))

# ---- competency: exclude patterns during packaging (out/release.zip) ----
def banned(rel):
    p = pathlib.PurePosixPath(rel).parts
    if any(c in p for c in EXCLUDE_DIRS):
        return True
    return p[-1].endswith(EXCLUDE_ENDINGS)

expected_shipped = []
for full in sorted((DATA / "pkg").rglob("*")):
    if not full.is_file():
        continue
    rel = full.relative_to(DATA / "pkg").as_posix()
    mode = full.stat().st_mode & 0o700
    if banned(rel) or mode == 0:
        continue
    expected_shipped.append(rel)
expected_shipped = sorted(expected_shipped)

rz = OUT / "release.zip"
if not rz.exists():
    fail("out/release.zip missing")
with zipfile.ZipFile(rz) as z:
    got = sorted(z.namelist())
if got != expected_shipped:
    fail("release.zip set mismatch\n  got=%s\n  want=%s" % (got, expected_shipped))
for n in got:
    if banned(n):
        fail("banned member shipped: %s" % n)

# ---- competency: symlink preserved + long/deep names (out/deep.tar.gz) ----
dt = OUT / "deep.tar.gz"
if not dt.exists():
    fail("out/deep.tar.gz missing")
try:
    with tarfile.open(dt, "r:gz", format=tarfile.PAX_FORMAT) as t:
        members = t.getmembers()
        names = set(t.getnames())
        syms = [mm for mm in members if mm.issym()]
        if not syms:
            fail("no symlink preserved in deep.tar.gz")
        sym = next((mm for mm in syms if mm.name.endswith("release_alias")), None)
        if sym is None:
            fail("release_alias symlink not present")
        base = sym.name.rsplit("/", 1)[0] if "/" in sym.name else "."
        resolved = posixpath.normpath(base + "/" + sym.linkname)
        if resolved not in names:
            fail("symlink target not a member: %r -> %r (resolved %r)"
                 % (sym.name, sym.linkname, resolved))
        longest = max((len(mm.name) for mm in members), default=0)
        if longest <= 100:
            fail("member names collapsed/truncated (max len %d)" % longest)
except (tarfile.TarError, OSError) as e:
    fail("bad deep.tar.gz: %r" % e)

# ---- competency: mirror tree into out/mirror under original basenames ----
mout = OUT / "mirror"
if not mout.is_dir():
    fail("out/mirror dir missing")
expected_m = {}
for full in sorted((DATA / "mirror_src").rglob("*.dat.gz")):
    expected_m[full.name[:-3]] = gzip.decompress(full.read_bytes())
for name, data in expected_m.items():
    fp = mout / name
    if not fp.is_file():
        fail("mirror: missing %s" % name)
    if fp.read_bytes() != data:
        fail("mirror: content mismatch %s" % name)

# ---- competency: hash every file under data/hash (integrity kept above) ----
hashroot = DATA / "hash"
expect_hash = {}
for full in sorted(hashroot.rglob("*")):
    if full.is_file():
        expect_hash[full.relative_to(hashroot).as_posix()] = \
            hashlib.sha256(full.read_bytes()).hexdigest()
got_hash = ans.get("hash")
if got_hash != expect_hash:
    fail("answer.hash mismatch (%d vs %d keys)" % (len(got_hash or {}), len(expect_hash)))

sys.exit(0)
PYEOF

fail=0

# visible case: the workspace the agent built (/app)
python3 /tmp/kcheck.py /app || fail=1

# hidden generalization cases
case_dirs=$(find /tests/hidden -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
if [ -z "$case_dirs" ]; then
  echo "kite-helix: no hidden cases mounted" >&2
  fail=1
else
  for d in $case_dirs; do
    ws="/tmp/hc_$(basename "$d")_$$"
    rm -rf "$ws"; mkdir -p "$ws"
    cp -a "$d/data" "$ws/data"
    python3 /tmp/kcheck.py "$ws" || fail=1
    rm -rf "$ws"
  done
fi

if [ "$fail" -eq 0 ]; then
  echo 1 > "$REWDIR/reward.txt"
else
  echo 0 > "$REWDIR/reward.txt"
fi
exit 0