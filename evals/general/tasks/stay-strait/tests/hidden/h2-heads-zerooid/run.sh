#!/bin/bash
# Hidden case h2: ref file under refs/heads/ whose contents are an
# all-zero 40-character object id (valid hex format, but a null OID). The
# upstream regression test corrupts the ref with content that is not hex at
# all; this input is perfectly well-formed hex yet still yields a null OID,
# exercising the same ref_transaction_create() null-OID path from an input
# the upstream test does not use. Must fail cleanly (rc 128, no BUG: line,
# a 'null OID' fatal diagnostic) on the fixed tree; on the pre-fix binary
# it must crash (abort, rc 134) instead.
set -u
GIT_BIN=${GIT_BIN:-/app/src/git}
work=$(mktemp -d /tmp/hc2.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
( mkdir -p "$work/src" && cd "$work/src" \
  && "$GIT_BIN" init -q \
  && "$GIT_BIN" config user.email t@t \
  && "$GIT_BIN" config user.name t \
  && echo one > one \
  && "$GIT_BIN" add one \
  && "$GIT_BIN" commit -q -m one ) || exit 1
printf '0000000000000000000000000000000000000000' > "$work/src/.git/refs/heads/zero" || exit 1
( cd "$work" && "$GIT_BIN" clone src dst ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 128 ] || { echo "expected clean failure rc=128, got $rc" >&2; exit 1; }
grep -q "has a null OID" "$work/out" || { echo "no 'has a null OID' diagnostic" >&2; exit 1; }
grep -q "^BUG:" "$work/out" && { echo "BUG: line present" >&2; exit 1; }
exit 0