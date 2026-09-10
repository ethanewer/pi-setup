#!/bin/bash
# reeve-gate verifier.
#
# The deliverable /app/setup_accounts.sh must bring a clean system to the exact
# account/privilege state described by a scenario JSON. This verifier:
#   1. checks the deliverable exists and is executable
#   2. checks the account tools are still the binaries this image built from
#      the pinned upstream (build-time sha256 snapshot) -- i.e. the agent used
#      its own built toolchain, not the distro's
#   3. rejects deliverable logic that hand-edits /etc/passwd & friends
#      (static scan of every file under /app)
#   4. replays the deliverable against every hidden scenario fixture starting
#      from the pristine account databases -- traced with strace -- and
#      (a) asserts every account-DB write was performed by a built shadow tool
#          (the deliverable must OPERATE the toolchain, not write the DBs),
#      (b) asserts the live end state with an independent state checker
set -u
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
mkdir -p /logs/verifier

FAILED=0

say_fail() {
    echo "FAIL: $*"
    FAILED=1
}

# ---- 1. deliverable present and executable ----
if [ ! -x /app/setup_accounts.sh ]; then
    echo "FAIL: /app/setup_accounts.sh is missing or not executable"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi
echo "ok: deliverable /app/setup_accounts.sh present"

# ---- 2. built-tool integrity: the binaries at canonical paths are the ones ----
# ----    installed at image build time from the pinned upstream ----
if ! (cd / && sha256sum -c /opt/reeve-gate/built-bins.sha256 > /tmp/reeve-sha.log 2>&1); then
    echo "FAIL: one or more account-management binaries do not match the build-time snapshot;"
    grep -v ': OK$' /tmp/reeve-sha.log | sed 's/^/    /'
    echo "the task requires operating the toolchain built from the pinned upstream source;"
    echo "an untouched distro binary or a tampered one does not satisfy that."
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi
echo "ok: account tools match the pinned build"

# ---- 3. the deliverable must OPERATE the toolchain, not edit the DBs ----
# Static first pass: scan EVERY file under /app (the deliverable and anything
# it may reference) for hand-edit constructs. This is a first line only; the
# decisive enforcement is the strace runtime check in step 4.
# Patterns: redirection into /etc DBs, cp/install/mv/tee/dd onto them, sed -i,
# perl -p/-i/-n/-e or awk -i, python open() with a write-like mode on the DBs.
DIRECT_EDIT_RE="(>>?[[:space:]]*[^ \t]*/etc/(passwd|shadow|gshadow|group)([^a-z]|$)"
DIRECT_EDIT_RE="${DIRECT_EDIT_RE}|(^|[[:space:]])((cp|install|mv|tee|dd)[[:space:]]+[^|]*/etc/(passwd|shadow|gshadow|group)([^a-z]|$))"
DIRECT_EDIT_RE="${DIRECT_EDIT_RE}|sed[[:space:]]+-i|perl[[:space:]]+-[pine]|awk[[:space:]]+-i"
DIRECT_EDIT_RE="${DIRECT_EDIT_RE}|open\([^)]*(passwd|shadow|gshadow)[^)]*['\"](w[ab+]*|a[ab+]*|r\+[ab]*)['\"])"
if grep -rIlE "$DIRECT_EDIT_RE" /app 2>/dev/null | grep -q .; then
    echo "FAIL: the deliverable (or a file it consults under /app) appears to write the"
    echo "account databases directly:"
    grep -rInE "$DIRECT_EDIT_RE" /app 2>/dev/null | head -10 | sed 's/^/    /'
    echo "direct hand-edits of /etc/passwd /etc/shadow /etc/group /etc/gshadow are forbidden;"
    echo "all account changes must go through the built shadow tools."
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi
TOOL_RE='(/usr/(sbin|bin))/(useradd|usermod|userdel|groupadd|groupdel|chpasswd|passwd|chage|newusers|gpasswd)'
if ! grep -Eq "$TOOL_RE" /app/setup_accounts.sh; then
    echo "FAIL: /app/setup_accounts.sh never invokes the built account-management tools"
    echo "(expected calls to useradd/usermod/groupadd/groupdel/userdel/chpasswd/passwd/chage)"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi
echo "ok: deliverable operates the built toolchain (static pass)"

# ---- 4. replay every hidden scenario from the pristine account databases,  ----
# ----    traced, with runtime tool-use enforcement and exact state checks ----
if ! command -v strace >/dev/null 2>&1; then
    echo "FAIL: strace is unavailable in this image; cannot enforce tool usage"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi
TRACE_SYS='open,openat,creat,rename,renameat,renameat2,unlink,unlinkat,execve'

CASES=0
for d in /tests/hidden/*/; do
    [ -d "$d" ] || continue
    scenario="$d/scenario.json"
    [ -f "$scenario" ] || { say_fail "missing scenario at $scenario"; continue; }
    CASES=$((CASES + 1))
    cname="$(basename "$d")"
    echo "== case: $cname =="

    if ! cp -a /opt/reeve-gate/pristine/etc/passwd /etc/passwd \
        || ! cp -a /opt/reeve-gate/pristine/etc/shadow /etc/shadow \
        || ! cp -a /opt/reeve-gate/pristine/etc/group /etc/group \
        || ! cp -a /opt/reeve-gate/pristine/etc/gshadow /etc/gshadow; then
        say_fail "could not restore pristine account databases (case $cname)"
        continue
    fi

    # wipe the prefixes the scenario declares, guarded to /srv/* only
    CLEANUP="$(python3 - "$scenario" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
for p in s.get("cleanup", []):
    if p.startswith("/srv/") and p != "/srv/":
        print(p)
PY
)"
    for p in $CLEANUP; do
        [ -n "$p" ] || continue
        rm -rf "$p"
    done

    # run the deliverable under strace: every create/write/rename/unlink of
    # the account DBs is attributed to an executable, so a script that
    # bypasses the built tools (direct DB writes, helper processes, or a
    # substitute binary) is caught here, not just by the static scan.
    if ! (cd /app && strace -f -e trace="$TRACE_SYS" -o "/tmp/reeve-trace-$cname.log" \
            timeout 240 /app/setup_accounts.sh "$scenario") > /tmp/reeve-run.out 2>&1; then
        echo "--- setup_accounts.sh exited nonzero (case $cname): ---"
        tail -25 /tmp/reeve-run.out | sed 's/^/    /'
        say_fail "setup_accounts.sh failed on case $cname"
        continue
    fi

    if ! python3 /tests/tool_use.py "/tmp/reeve-trace-$cname.log" > /tmp/reeve-tools.out 2>&1; then
        echo "--- toolchain-not-operated (case $cname): ---"
        grep '^DB-WRITE-VIOLATION' /tmp/reeve-tools.out | sed 's/^/    /' | head -12
        say_fail "account DBs were written by a process other than the built tools (case $cname)"
        continue
    fi

    if ! python3 /tests/check_state.py "$scenario" > /tmp/reeve-state.out 2>&1; then
        echo "--- state mismatches (case $cname): ---"
        sed -n 's/^MISMATCH:/    /p' /tmp/reeve-state.out | head -25
        say_fail "live state does not match scenario $cname"
        continue
    fi
    echo "case $cname: PASS"
done

if [ "$CASES" -eq 0 ]; then
    echo "FAIL: no hidden scenario fixtures found under /tests/hidden/"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

if [ "$FAILED" -eq 1 ]; then
    echo "VERDICT: 0"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

echo "VERDICT: 1 (all hidden cases passed on the built toolchain)"
echo 1 > /logs/verifier/reward.txt
exit 0