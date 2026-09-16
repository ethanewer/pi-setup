#!/usr/bin/env bash
# oracle for figurehead-grapnel: write the reproduction deliverable, apply the
# fix, rebuild from source, and prove both directions.
set -u

REPO=/app/curl
BIN="/app/curl/src/curl"
REPRO=/app/reproduce_bug.sh

# --- deliverable 1: the failing reproduction (the real solver content) ---
cp /solution/reproduce_bug.sh "$REPRO"
chmod +x "$REPRO"

# --- prove the pre-fix behaviour first: the reproduction MUST fail here ---
if "$REPRO" "$BIN" >/tmp/oracle-prefix.log 2>&1; then
    echo "pre-fix binary does not show the bug; aborting rather than shipping a vacuous fix" >&2
    exit 1
fi
echo "pre-fix reproduction fails as required (bug is present)"

# --- deliverable 2: fix the source, then rebuild it into /app/curl/src/curl ---
cd "$REPO" || exit 1
if ! grep -q 'strcmp(imap->mailbox, imapc->mailbox)' lib/imap.c; then
    patch -p1 --forward -s < /solution/imap-fix.patch || { echo "applying the fix patch failed" >&2; exit 1; }
fi
make -j1 >/dev/null 2>&1 || { echo "make failed" >&2; exit 1; }
[ -x "$BIN" ] || { echo "rebuild did not produce $BIN" >&2; exit 1; }

# --- prove the post-fix behaviour: the reproduction MUST pass now ---
if ! "$REPRO" "$BIN" >/tmp/oracle-postfix.log 2>&1; then
    echo "reproduction still fails after the fix" >&2
    cat /tmp/oracle-postfix.log >&2
    exit 1
fi
echo "post-fix reproduction passes (2 SELECT commands on the wire)"
echo "ORACLE OK"