#!/bin/bash
# meadow-bridge verifier. Executes /app/solve.py on the visible archive and on
# hidden archives; checks answer fields, extracted bytes, ISO content, ACL
# inheritance, and source immutability. Writes /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "meadow-bridge FAIL: $1" >&2; ok=0; }

VISIBLE_TAR_SHA=7c7f8db5cc726d31f821e6c2d128070a96788ee7f21098f7a93d62e11d0018e6

check_case() {
  # check_case <tar> <config> <expected.json> <outdir> <label> <known_sha|->
  local tar="$1" cfg="$2" exp="$3" out="$4" label="$5" known="$6"
  local before after
  before=$(sha256sum "$tar" | cut -d' ' -f1)
  if ! python3 /app/solve.py "$tar" "$cfg" "$out" > /tmp/mb.log 2>&1; then
    fail "$label: solve.py exited nonzero"; sed 's/^/  /' /tmp/mb.log >&2
    return
  fi
  after=$(sha256sum "$tar" | cut -d' ' -f1)
  if [ "$before" != "$after" ]; then fail "$label: source archive modified"; fi
  if [ "$known" != "-" ] && [ "$after" != "$known" ]; then
    fail "$label: source archive bytes changed"
  fi
  local ans="$out/answer.json"
  [ -f "$ans" ] || { fail "$label: answer.json missing"; return; }
  python3 - "$ans" "$exp" "$out" "$tar" <<'PY' || fail "$label: answer/structural checks failed"
import json, os, subprocess, sys, tarfile
ans, exp, out, tar = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
got = json.load(open(ans))
want = json.load(open(exp))
for key in ("extracted", "symlinks_preserved", "file_count", "hashes", "relocations"):
    if got.get(key) != want[key]:
        print(f"mismatch: {key}", file=sys.stderr); sys.exit(1)
# extracted bytes must equal the archive member content
with tarfile.open(tar, "r:gz") as tf:
    blob = tf.extractfile(want["extracted"]).read()
if open(os.path.join(out, "extracted.bin"), "rb").read() != blob:
    print("extracted.bin content mismatch", file=sys.stderr); sys.exit(1)
# iso exists, self-consistent size, and lists toolchain content
iso = os.path.join(out, "release.iso")
if not os.path.isfile(iso) or got.get("iso_size") != os.path.getsize(iso):
    print("iso missing or size mismatch", file=sys.stderr); sys.exit(1)
listing = subprocess.run(["isoinfo", "-R", "-i", iso, "-f"],
                         capture_output=True, text=True).stdout
if "/runner" not in listing or "/core.dat" not in listing:
    print("iso does not list toolchain files", file=sys.stderr); sys.exit(1)
# acl: group field, live acl on shared, default acl inherited by a fresh child
shared = got["acl"]["shared_dir"]
grp = got["acl"]["group"]
if not os.path.isdir(shared):
    print("shared dir missing", file=sys.stderr); sys.exit(1)
live = subprocess.run(["getfacl", "-p", shared], capture_output=True, text=True).stdout
if f"group:{grp}:r-x" not in live:
    print("live acl missing", file=sys.stderr); sys.exit(1)
child = os.path.join(shared, "probe_child")
os.makedirs(child, exist_ok=True)
child_acl = subprocess.run(["getfacl", "-p", child], capture_output=True, text=True).stdout
if f"group:{grp}:r-x" not in child_acl:
    print("default acl not inherited", file=sys.stderr); sys.exit(1)
PY
}

# visible case: deliverables must exist from the agent's own run, and the
# pipeline must be reproducible on demand
if [ ! -f /app/out/answer.json ] || [ ! -f /app/out/release.iso ]; then
  fail "visible deliverables missing (/app/out/answer.json or release.iso)"
fi
check_case /app/release.tar.gz /app/config.json /tests/hidden/visible_expected.json \
  /tmp/mb_visible visible "$VISIBLE_TAR_SHA"

for c in a b; do
  check_case "/tests/hidden/$c/release.tar.gz" "/tests/hidden/$c/config.json" \
    "/tests/hidden/$c/expected.json" "/tmp/mb_$c" "hidden-$c" "-"
done

[ $ok -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "meadow-bridge reward=$reward" >&2
