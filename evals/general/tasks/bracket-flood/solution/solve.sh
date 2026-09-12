#!/bin/bash
# bracket-flood oracle: guard the relative-TTL addition in redis's
# RESTORE handler against signed 64-bit overflow, rebuild incrementally,
# prove the symptom is gone with the installed reproducer, and write the
# root-cause write-up. The fix is the one upstream adopted, confined to the
# single command handler that computes the expiry.
set -eu

SRC=/app/src

# ---- 1. Apply the fix to the source tree (real work, no hardcoding). ----
python3 - <<'PY'
path = '/app/src/src/cluster.c'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

anchor = '        if (!absttl) ttl+=commandTimeSnapshot();'
guard = ('        if (!absttl && add_overflow_ll(ttl, commandTimeSnapshot(), &ttl)) {\n'
         '            addReplyErrorExpireTime(c);\n'
         '            return;\n'
         '        }')

assert 'add_overflow_ll' not in src, 'guard already present; nothing to fix'
assert src.count(anchor) == 1, 'anchor line not unique; source differs from snapshot'
src = src.replace(anchor, guard)
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src)
print('fixed: restoreCommand now refuses a relative TTL whose addition overflows')
PY

# ---- 2. Rebuild incrementally so the running binary reflects the fix. ----
( cd "$SRC" && make -j1 > /tmp/oracle-make.log 2>&1 )

# ---- 3. Prove the symptom is gone using the installed reproducer. ----
out=$(bash /app/reproduce.sh 2>&1); rc=$?
echo "$out" | grep -E "restore result|restore \(replace|key exists after|value still readable|expired_keys"
case "$out" in
  *'caught=1'*'invalid expire time'*) ;;
  *) echo "oracle smoke: reproducer did not show the error reply"; exit 1 ;;
esac
case "$out" in
  *'expired_keys: before='*' after='*) ;;
esac
[ "$rc" -eq 0 ] || { echo "oracle smoke: reproducer exited $rc"; exit 1; }

# ---- 4. Root-cause write-up. ----
cat > /app/diagnosis.md <<'MD'
# Diagnosis: RESTORE silently drops keys on an oversized relative TTL

## Symptom

`RESTORE key <huge-ttl> <dump>` (relative TTL, e.g. 9223372036854775807)
replies `OK` but the restored key is immediately gone: EXIST returns 0
right away. With REPLACE the previous value is deleted as well, and the
server's `expired_keys` counter increments even though no key aged.

## Root cause

The RESTORE handler converts a relative TTL to an absolute expiry by adding
the current command time to it:

    if (!absttl) ttl += commandTimeSnapshot();

It never checks that the addition overflows. When the caller passes a TTL
close to INT64_MAX, the sum wraps around to a large negative "timestamp".
The key is then stored with that negative expiry and the code path that
handles already-expired keys fires immediately: the command replies OK and
the key is removed (and counted as expired) right away, silently.

## Fix

Guard the addition: compute `ttl + commandTimeSnapshot()` with overflow
detection (`add_overflow_ll`). If the sum would overflow, refuse the command
with the standard "invalid expire time in 'restore' command" error before
anything is written, leaving an existing key (REPLACE) untouched. The ABSTTL
path is not affected, so large absolute timestamps remain valid.
MD

# ---- 5. The project's own dump suite must stay green. ----
( cd "$SRC" && ./runtest --single unit/dump > /tmp/oracle-suite.log 2>&1 )

echo "oracle done: guarded handler, rebuilt src/redis-server, wrote /app/diagnosis.md"