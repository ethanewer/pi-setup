#!/usr/bin/env bash
#
# vine-helix verifier.
# Boots from pristine (or after the agent) and confirms every repaired
# subsystem holds, then re-runs the fixperms deliverable against hidden trees.
# Writes a numeric reward to /logs/verifier/reward.txt (0 or 1).
set -u
mkdir -p /logs/verifier
ok=1
fail(){ echo "FIELD: $*"; ok=0; }
SECRET='PetalGrove-74Rook'

# ---------- A. deliverables present & executable ----------
[ -f /app/configure.sh ] && [ -x /app/configure.sh ] || fail "missing/not-exec /app/configure.sh"
[ -f /app/fixperms.sh ]  && [ -x /app/fixperms.sh ]  || fail "missing/not-exec /app/fixperms.sh"
[ -f /app/dump.txt ]                                 || fail "missing /app/dump.txt"

# idempotent re-run of the primary deliverable
if ! bash /app/configure.sh >/tmp/cfg.log 2>&1; then
  fail "configure.sh re-run exited non-zero; tail:"; tail -4 /tmp/cfg.log | sed 's/^/  /' >&2
fi

# ---------- B. password-based auth for account juna ----------
python3 - "$SECRET" <<'PY' || fail "password auth not enabled for juna"
import sys, crypt, spwd
secret = sys.argv[1]
e = spwd.getspnam("juna")
h = e.sp_pwdp
assert h and not h.startswith(("!", "*")), "account locked or blank"
assert crypt.crypt(secret, h) == h, "submitted secret does not verify"
PY
# sshd config enabled for password-based logins
grep -rq '^PasswordAuthentication[[:space:]]*yes' /etc/ssh/sshd_config.d/ || fail "PasswordAuthentication not enabled"

# ---------- C. outsiders denied vs group members allowed ----------
if su -s /bin/bash broka -c 'cat /app/shared/metrics/file1.csv' >/dev/null 2>&1; then
  fail "non-member brosia could read shared group data"
fi
if ! su -s /bin/bash juna -c 'cat /app/shared/metrics/file1.csv' >/dev/null 2>&1; then
  fail "group member juna denied read of shared data"
fi

# ---------- D. group scripts restored (execute + read) ----------
[ "$(stat -c '%G' /app/shared/scripts)" = "petal" ] || fail "scripts dir not owned by group petal"
for f in /app/shared/scripts/*.sh; do
  [ -e "$f" ] || continue
  [ -r "$f" ] && [ -x "$f" ] || fail "script not readable+executable: $f"
done
[ -d /app/shared ] || fail "missing shared area"
g=$(stat -c '%a' /app/shared)
case "$g" in
  7[0-5][0-7]|6[0-5][0-7]) : ;;
  *) fail "shared area mode not group-accessible (got $g)" ;;
esac

# ---------- E. cProfile stats + band ----------
python3 - <<'PY' || fail "profile stats/band invalid"
import pstats, re
for name in ("digest", "refine"):
    pstats.Stats("/app/prof/%s_slow.stats" % name)   # raises if unreadable
    pstats.Stats("/app/prof/%s_fast.stats" % name)
band = open("/app/prof/band.txt").read()
for name in ("digest", "refine"):
    m = re.search(r"%s: slow=([0-9.]+) fast=([0-9.]+) faster_ok=(yes|no)" %
                  name, band)
    assert m, "missing band entry for " + name
    s, f, oktag = float(m.group(1)), float(m.group(2)), m.group(3)
    assert oktag == "yes", "improvement band not accepted for " + name
    assert f < 1.0 and f < s, "fast total not below floor for " + name
PY

# ---------- F. node trial checker report ----------
python3 - <<'PY' || fail "results.json missing/invalid or not all PASS"
import json
r = json.load(open("/app/results/results.json"))
s = r["summary"]
assert s["total"] == 3 and s["failed"] == 0 and s["passed"] == 3, s
exp = {"alpha": 7, "beta": 11, "gamma": 5}
for t in r["trials"]:
    assert t["status"] == "PASS", t
    assert t["expected"] == exp[t["id"]], t
PY

# re-run the bundled runner on hidden trial layouts (left-behind solver)
if [ -d /tests/hidden/runner ]; then
  for tb in /tests/hidden/runner/*.trial.json; do
    [ -e "$tb" ] || continue
    sb="${tb%.trial.json}.solution.json"
    [ -f "$sb" ] || continue
    out=/tmp/pr_$(basename "$tb").json
    if ! node /app/check/runner.mjs "$tb" "$sb" "$out" >/tmp/pr.log 2>&1; then
      fail "hidden runner rejected layout set $(basename "$tb")"
    else
      python3 - "$out" <<'PY' || fail "hidden runner report inconsistent"
import sys, json
r = json.load(open(sys.argv[1]))
assert r["summary"]["failed"] == 0 and r["summary"]["passed"] == r["summary"]["total"]
for t in r["trials"]:
    assert t["status"] == "PASS", t
PY
    fi
  done
fi

# ---------- G. dump.txt verbatim ----------
bash /app/finish.sh > /tmp/exp_banner
cmp -s /app/dump.txt /tmp/exp_banner || fail "dump.txt does not capture ending text verbatim"

# ---------- H. lifecycle files purged ----------
[ ! -e /app/registry/registry.conf ] || fail "registry.conf lifecycle file still present"
[ ! -e /app/registry/gw.pid ]        || fail "gw.pid lifecycle file still present"

# ---------- I. in-flight cleanup on cancellation ----------
if ! bash /app/cleanup/run_tester.sh >/tmp/cl.log 2>&1; then
  fail "cleanup did not run on cancellation ($(tac /tmp/cl.log | tr '\n' ' '))"
fi

# ---------- J. fixperms.sh on hidden trees ----------
if [ -d /tests/hidden/fix ]; then
  for f in /tests/hidden/fix/*/; do
    [ -d "$f" ] || continue
    case_name=$(basename "$f")
    w=/tmp/fxp_$case_name; rm -rf "$w"
    cp -a "$f/work" "$w"
    # restore the intended broken initial modes (host copies are readable for
    # the task checksumming; the scenario starts from restrictive modes)
    case "$case_name" in
      f1) chmod 000 "$w/a.sh" "$w/b.sh" ;;
      f2) chmod 111 "$w/run.sh"; chmod 000 "$w/exec_only.sh" ;;
    esac
    if ! bash /app/fixperms.sh "$w" >/dev/null 2>&1; then
      fail "fixperms.sh failed on hidden tree $case_name"
      continue
    fi
    while read -r rel mode; do
      [ -n "$rel" ] || continue
      if [ "$rel" = "ABSENT" ]; then
        [ ! -e "$w/_absent_" ] || fail "$case_name: unexpected abs file"
        continue
      fi
      [ -e "$w/$rel" ] || { fail "$case_name: missing $rel"; continue; }
      got=$(stat -c '%a' "$w/$rel")
      [ "$got" = "$mode" ] || fail "$case_name: mode of $rel is $got (want $mode)"
    done < "$f/expected.txt"
  done
  # edge: nonexistent target directory must be a graceful no-op (exit 0)
  if ! bash /app/fixperms.sh /tmp/fxp_nonexistent_xyz >/dev/null 2>&1; then
    fail "fixperms.sh failed on nonexistent target directory"
  fi
fi

# ---------- reward ----------
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0