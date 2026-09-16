#!/bin/bash
# bracket-bight oracle: apply the upstream fix to the real express tree at
# /app/src and prove the user-facing reproducer now succeeds.
#
# res.send() must not populate Content-Length on a response that already
# declares a Transfer-Encoding header: HTTP/1.1 forbids carrying both, and
# Node's own HTTP client rejects such a response with "Content-Length can't
# be present with Transfer-Encoding", so the body never reaches the client.
# The fix is the one-condition guard upstream added for this bug.
set -eu

python3 - <<'PY'
path = '/app/src/lib/response.js'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

old = "  if (chunk !== undefined) {"
new = "  if (chunk !== undefined && !this.get('Transfer-Encoding')) {"

hits = src.count(old)
assert hits == 1, 'expected exactly one Content-Length population site, found %d' % hits
assert new not in src, 'guard already present; tree not at the pre-fix parent'
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src.replace(old, new))
print('patched: Content-Length is no longer populated when the response '
      'already carries a Transfer-Encoding header')
PY

# Syntax-check the touched file, then run the user-facing reproducer: it must
# print "Content-Length present: false | Transfer-Encoding present: true"
# and exit 0, which is the observable fix.
node --check /app/src/lib/response.js
cd /app/src
node /app/reproduce.js