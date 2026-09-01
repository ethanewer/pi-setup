#!/bin/bash
# Verifier for zephyr-engine. Runs as root, reads /tests (read-only), writes
# the numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "FAIL: $*" >&2; ok=0; }

EXP=/tests/expected.json
HIDDEN=/tests/hidden
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# 0) Deliverables exist
# ---------------------------------------------------------------------------
for f in /app/solve.py /app/scrub.py /app/upload/sanitizer.py \
         /app/candidates.txt /app/answer.json /app/creds.txt /app/vault.hash; do
  [ -e "$f" ] || fail "missing deliverable $f"
done
[ -d /app/team ] || fail "missing repo /app/team"

# ---------------------------------------------------------------------------
# 1) Re-run the solver standalone; it must regenerate artifacts.
# ---------------------------------------------------------------------------
python3 /app/solve.py > /dev/null 2>&1 || fail "solve.py did not run cleanly"

# ---------------------------------------------------------------------------
# 2) Candidate file: all lines well-formed per the schedule; contains password.
# ---------------------------------------------------------------------------
EXP_PW=$(python3 -c 'import json;print(json.load(open("/tests/expected.json"))["password"])')
nlines=$(wc -l < /app/candidates.txt)
if [ "$nlines" -lt 1 ]; then fail "candidates.txt empty"; fi
python3 - /app/candidates.txt <<'PY' || fail "candidates.txt not well-formed"
import sys, zephyr_gen as z
lines=[l.strip() for l in open(sys.argv[1]) if l.strip()]
assert lines, "no lines"
for t in lines:
    assert z.is_well_formed(t), "non-conforming line: "+t
assert len(lines)==len(set(lines)), "duplicate line"
PY
grep -qxF "$EXP_PW" /app/candidates.txt || fail "password not listed among candidates"

# ---------------------------------------------------------------------------
# 3) answer.json content correctness + password really decrypts the vault.
# ---------------------------------------------------------------------------
python3 - "$EXP_PW" "$WORK" <<'PY' || fail "answer/extraction check failed"
import json, sys, subprocess, os, hashlib
pw=sys.argv[1]; work=sys.argv[2]
exp=json.load(open("/tests/expected.json"))
ans=json.load(open("/app/answer.json"))
for k in ("password","active_seed","candidate_count","beacon","probed",
          "member","creds_user","creds_secret","endpoint"):
    assert k in ans, "answer.json missing key "+k
assert ans["password"]==exp["password"], ("wrong password", ans["password"])
assert ans["beacon"]==17, ("beacon", ans["beacon"])
assert ans["active_seed"]==exp["seed"], ("seed", ans["active_seed"])
assert int(ans["candidate_count"])==int(exp["candidate_count"]), ("candidate_count", ans["candidate_count"])
assert ans["probed"] is True, "probed not true"
assert ans["creds_user"]==exp["creds_user"], ("user",ans["creds_user"])
assert ans["creds_secret"]==exp["creds_secret"], ("secret",ans["creds_secret"])
assert ans["endpoint"]==exp["endpoint"], ("endpoint",ans["endpoint"])

# Independent re-extraction with the answer password must yield the creds.
out=os.path.join(work,"x")
os.makedirs(out)
r=subprocess.run(["7z","x","-y","-p"+ans["password"],"-o"+out,"/app/vault.7z"],
                 capture_output=True,text=True)
assert r.returncode==0, ("7z rc",r.returncode)
got=open(os.path.join(out,exp["vault_member"])).read()
assert got==exp["creds"], ("decrypted creds mismatch", got[:40])

# /app/creds.txt is the real decrypted member
assert open("/app/creds.txt").read()==exp["creds"], "/app/creds.txt mismatch"

# /app/vault.hash probe reflects AES-256 encryption
probe=open("/app/vault.hash").read()
assert "AES" in probe, "probe has no AES encryption"
print("answer+extraction OK")
PY
# shell needs to know the python block result; if it failed, fail below via $?

# ---------------------------------------------------------------------------
# 4) /app/team is scrubbed: no secret-token regex anywhere, backup files gone.
# ---------------------------------------------------------------------------
python3 - <<'PY' || fail "team not scrubbed"
import os, re
PAT=re.compile(r"[A-Z0-9]{3}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2}")
hits=0
for dp,_,fns in os.walk("/app/team"):
    for fn in fns:
        p=os.path.join(dp,fn)
        if os.path.splitext(fn.lower())[1] in (".bak",".orig",".tmp"):
            assert False, "backup file still present: "+p
        txt=open(p,"r",errors="ignore").read()
        if PAT.search(txt):
            raise SystemExit("secret regex still in "+p)
assert True
PY

# ---------------------------------------------------------------------------
# 5) Sanitizer harness (visible) + hidden lists from /tests/hidden.
# ---------------------------------------------------------------------------
run_uploads() {  # $1 = file of dangerous names, $2 = file of safe names (or '')
  python3 - "$1" "$2" <<'PY' || return 1
import sys
import importlib.util
spec=importlib.util.spec_from_file_location("san","/app/upload/sanitizer.py")
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
f=m.sanitize_upload_filename
danger=open(sys.argv[1]).read().splitlines() if sys.argv[1] else []
for line in danger:
    line=line.strip()
    if not line: continue
    assert f(line)=="", ("dangerous not rejected", line, f(line))
safe=open(sys.argv[2]).read().splitlines() if sys.argv[2] else []
for line in safe:
    line=line.strip()
    if not line: continue
    assert f(line)==line, ("safe altered", line, f(line))
# fixed edge cases
for bad in ("..","../etc/passwd","a\\b.jsp","..\\..","weapon.jar.jsp","x.jsp"):
    assert f(bad)=="", ("edge not rejected", bad, f(bad))
for good in ("ok.jar","report.zip","schema.json","a.b.txt"):
    assert f(good)==good, ("edge safe altered", good, f(good))
PY
}

# visible main cases supplied inline
run_uploads /dev/null /dev/null || fail "sanitizer (visible) failed"

# hidden upload scalar lists
HID_DANG="${HIDDEN:-/tests/hidden}"
if [ -d "$HIDDEN" ]; then
  for f in "$HIDDEN"/uploads_danger_*.txt; do
    [ -e "$f" ] || continue
    run_uploads "$f" /dev/null || fail "hidden uploads danger $f"
  done
  for f in "$HIDDEN"/uploads_safe_*.txt; do
    [ -e "$f" ] || continue
    run_uploads /dev/null "$f" || fail "hidden uploads safe $f"
  done
fi

# ---------------------------------------------------------------------------
# 6) Hidden scrub fixtures: copy to writable /tmp, run scrub, verify clean.
# ---------------------------------------------------------------------------
scrub_check() {  # $1 = fixture dir, $2 = expected non-empty flag
  local root
  root="$WORK/scrub_$(basename "$1")"
  cp -a "$1" "$root"
  python3 /app/scrub.py "$root" > "$WORK/scrub_out.json" 2>/dev/null || { fail "scrub.py failed on $1"; return; }
  python3 - "$root" <<'PY' || fail "scrub left tokens in $1"
import os,re,sys
PAT=re.compile(r"[A-Z0-9]{3}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2}")
for dp,_,fns in os.walk(sys.argv[1]):
    for fn in fns:
        p=os.path.join(dp,fn)
        if os.path.splitext(fn.lower())[1] in (".bak",".orig",".tmp"):
            raise SystemExit("backup remains")
        assert not PAT.search(open(p,"r",errors="ignore").read()), "token remains "+p
PY
}

if [ -d "$HIDDEN" ]; then
  for d in "$HIDDEN"/scrub_*; do [ -e "$d" ] && scrub_check "$d"; done
  # sanity: the fixture must have actually contained a token
  for d in "$HIDDEN"/scrub_*; do
    [ -e "$d" ] || continue
    found=$(grep -rlE "[A-Z0-9]{3}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2}" "$d" 2>/dev/null | wc -l )
    [ "$found" -ge 1 ] || fail "hidden scrub fixture $d has no token"
  done
fi

# ---------------------------------------------------------------------------
[ "$ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0