#!/usr/bin/env bash
# Shared final-state assertion library for the brisk-atlas verifier.
# Sourced by tests/test.sh and every tests/hidden/*.sh case.

F1=/opt/tools-scripts/deprecated.sh
F2=/opt/tools-scripts/legacy.sh
SHARED=/srv/team/shared
ARCH=/app/workspace.tar
TOKEN=/var/lib/brk/rootgate/atlas-client.token
BUCKET=/app/portable-bucket
RC=/home/alice/.bashrc
OUT=/app/audit.txt

_fail() { echo "CHECK-FAIL: $*"; return 1; }
_ok()  { echo "  ok: $*"; }

# Compare archive listing perms/owner/mtime against the normalization spec.
check_archive() {
  local listing dircnt filecnt bad
  [ -f "$ARCH" ] || return $(_fail "archive $ARCH missing")
  listing=$(tar --full-time -tvf "$ARCH" 2>/dev/null) || { _fail "cannot list archive"; return 1; }
  dircnt=$(printf '%s\n' "$listing" | grep -c '^drwx------') || true
  filecnt=$(printf '%s\n' "$listing" | grep -c '^-rw-------') || true
  [ "$dircnt" -ge 1 ] || { _fail "no 700-mode directory member in archive"; return 1; }
  [ "$filecnt" -ge 1 ] || { _fail "no 600-mode file member in archive"; return 1; }
  badowner=$(printf '%s\n' "$listing" | awk '$2 != "root/root"{print;c=1} END{if(c)print ""}')
  [ -z "$badowner" ] || { _fail "archive member owner not normalized: $badowner"; return 1; }
  badtime=$(printf '%s\n' "$listing" | awk '$4 != "2000-01-01" || $5 != "00:00:00"{print;c=1} END{if(c){print ""}}')
  [ -z "$badtime" ] || { _fail "archive mtime not normalized: $badtime"; return 1; }
  _ok "archive normalized (dirs=700 files=600 owner=root/root mtime=2000-01-01)"
}

# Directory + group + setgid + child inheritance.
check_setgid() {
  [ -d "$SHARED" ] || { _fail "shared dir missing"; return 1; }
  local g p
  g=$(stat -c %G "$SHARED") || return 1
  p=$(stat -c %A "$SHARED")
  [ "$g" = devteam ] || { _fail "shared dir group=$g (want devteam)"; return 1; }
  [[ "$p" == drwxrws* ]] || { _fail "shared dir perms=$p (want setgid 27xx)"; return 1; }
  local child
  child=$(runuser -u alice -- bash -c 'f=/srv/team/shared/probe-$$; touch "$f" && stat -c %G "$f"; rc=$?; rm -f "$f"; exit $rc' 2>/dev/null) || { _fail "cannot create child as alice"; return 1; }
  [ "$child" = devteam ] || { _fail "child inherits group $child (want devteam)"; return 1; }
  _ok "setgid shared dir group=devteam, mode=$p, children inherit"
}

# Strip-exec scripts: present, non-executable, untouched bytes, never run.
check_scripts() {
  for f in "$F1" "$F2"; do
    [ -f "$f" ] || { _fail "script missing $f"; return 1; }
    [ -x "$f" ] && { _fail "script still executable $f"; return 1; }
  done
  local a b m1 m2
  a=$(md5sum "$F1" | awk '{print $1}')
  b=$(md5sum "$F2" | awk '{print $1}')
  m1='e640d881cc9176c094beba6a011adc2d'
  m2='8699892d1e9b2d267b5d78f9eeb0ef0f'
  [ "$a" = "$m1" ] || { _fail "deprecated.sh content changed"; return 1; }
  [ "$b" = "$m2" ] || { _fail "legacy.sh content changed"; return 1; }
  # If any script had been executed a side-effect marker would be present.
  for mark in /run/brisk-deprecated-ran /run/brisk-legacy-ran; do
    [ -e "$mark" ] && { _fail "script was executed (marker $mark present)"; return 1; }
  done
  _ok "scripts non-executable, byte-identical, never executed"
}

# Escalated vault removal.
check_vault() {
  [ ! -e /opt/secret/root/client.bin ] || { _fail "root-protected client.bin still present"; return 1; }
  [ -d /opt/secret/root ] || { _fail "vault dir   disappeared"; return 1; }
  _ok "root-protected client.bin removed (vault dir intact)"
}

# sudo-bridge capability: token exists in root-only gate, and a fresh
# invocation through the sudo rule still mints one.
check_capability() {
  [ -r "$TOKEN" ] || { _fail "capability token missing at $TOKEN"; return 1; }
  [ -s "$TOKEN" ] || { _fail "capability token empty"; return 1; }
  local tm
  tm=$(runuser -u alice -- sudo -n /opt/objsvc/bridge token probe-$$ 2>/dev/null) || : 
  [ -f /var/lib/brk/rootgate/probe-$$.token ] || { _fail "sudo rule fails to mint token"; return 1; }
  _ok "capability token minted via sudo-allowed bridge"
}

# ACL public read.
check_acl() {
  local other
  other=$(getfacl -cp "$BUCKET" 2>/dev/null | grep '^other::' | head -n1)
  case "$other" in
    other::r--*) _ok "bucket other::$other" ;;
    *) _fail "bucket other ACL is '$other' (want other::r--)"; return 1 ;;
  esac
}

# rc environment persisted.
check_rc() {
  grep -q 'export BRISK_HOME=/opt/brisk' "$RC" || { _fail "no BRISK_HOME in rc"; return 1; }
  grep -q 'BRISK_HEADERS' "$RC" || { _fail "no BRISK_HEADERS in rc"; return 1; }
  local got
  got=$(runuser -u alice -- bash -i -c 'echo "$BRISK_HOME" 2>/dev/null' 2>/dev/null | tail -n1)
  [ "$got" = /opt/brisk ] || { _fail "fresh shell BRISK_HOME='$got' (want /opt/brisk)"; return 1; }
  _ok "Brisk tool env persisted and visible in fresh shell"
}

# audit report deliverable.
check_audit() {
  [ -s "$OUT" ] || { _fail "audit.txt missing/empty"; return 1; }
  for kw in setg-dir archive scripts vault-remove capability bucket-acl rc; do
    grep -q "$kw" "$OUT" || { _fail "audit.txt missing keyword $kw"; return 1; }
  done
  _ok "audit.txt report present with expected sections"
}

check_final_state() {
  check_setgid || return $?
  check_archive || return $?
  check_scripts || return $?
  check_vault || return $?
  check_capability || return $?
  check_acl || return $?
  check_rc || return $?
  check_audit || return $?
}