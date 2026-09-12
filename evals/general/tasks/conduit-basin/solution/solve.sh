#!/bin/bash
# conduit-basin oracle: fix --bigkeys/--keystats so a zero-size key is
# reported as the biggest of its type, rebuild incrementally, and prove the
# symptom is gone with the installed reproducer.
#
# The fix is the one upstream adopted, confined to the two per-type
# biggest-key bookkeeping functions in the redis-cli sources:
#   * the strict '<' comparisons (type->biggest starts at 0, so a zero-size
#     key is never strictly larger) gain an alternative condition that
#     records a size-0 key when no biggest key has been recorded yet,
#   * the TTY progress-bar guard keys off biggest_key instead of a > 0 size.
set -eu

SRC=/app/src

# ---- 1. Apply the fix to the source tree (real work, no hardcoding). ----
python3 - <<'PY'
path = '/app/src/src/redis-cli.c'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

subs = [
    # findBigKeys(): remember a zero-size key when no biggest key is set yet
    ('if(type->biggest<sizes[i]) {',
     'if(type->biggest<sizes[i] || (!type->biggest_key && type->sizecmd)) {'),
    # TTY progress path: show the type once a biggest key exists, even at 0
    ('if (current_type->biggest > 0) {',
     'if (current_type->biggest_key) {'),
    # updateKeyType() (--keystats path): same rule as findBigKeys
    ('if (type->biggest<size) {',
     'if (type->biggest<size || (!type->biggest_key && type->sizecmd)) {'),
]

for old, new in subs:
    assert src.count(old) == 1, 'anchor not unique or missing: %r' % old
    src = src.replace(old, new)

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src)
print('fixed: zero-size keys are now recorded as biggest of their type')
PY

# ---- 2. Rebuild incrementally so the running binary reflects the fix. ----
( cd "$SRC" && make -j1 > /tmp/oracle-make.log 2>&1 )

# ---- 3. Prove the symptom is gone using the installed reproducer. ----
out=$(bash /app/reproduce.sh 2>&1); rc=$?
echo "$out" | grep -E "Biggest string|string \"empty\"|STATE=" | sed 's/^/    /'
case "$out" in
  *'STATE=FIXED'*) ;;
  *) echo "oracle smoke: reproducer did not report STATE=FIXED (rc=$rc)"; exit 1 ;;
esac
case "$out" in
  *'Biggest string found "empty" has 0 bytes'*) ;;
  *) echo "oracle smoke: --bigkeys did not print the zero-size biggest line"; exit 1 ;;
esac
case "$out" in
  *'string "empty" has 0B'*) ;;
  *) echo "oracle smoke: --keystats did not print the zero-length entry"; exit 1 ;;
esac

echo "oracle smoke: reproducer shows STATE=FIXED in both modes"