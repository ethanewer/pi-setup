#!/bin/bash
# bracket-bell oracle: fix the comment-only-credentials-file segfault in the
# real curl tree, rebuild the binary, and write the root-cause write-up.
# The fix is the same one upstream adopted: when the loaded credentials file
# parses to an EMPTY buffer (comment-only or empty file), return
# "no match" before handing the empty buffer to the scanner, whose tokenizer
# dereferences the NULL content pointer. The check harness lives under
# the project tree and is not read here.
set -eu

SRC=/app/src

# ---- 1. Apply the fix to the source tree (real work, no hardcoding). ----
python3 - <<'PY'
path = '/app/src/lib/netrc.c'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

anchor = '  return netrc_scan(data, curlx_dyn_ptr(filebuf), hostname, user, pcreds);'
guard = '  if(!curlx_dyn_len(filebuf))\n    return NETRC_NO_MATCH;\n\n'

assert 'curlx_dyn_len(filebuf)' not in src, 'guard already present; nothing to fix'
assert src.count(anchor) == 1, 'anchor line not unique; source differs from snapshot'
src = src.replace(anchor, guard + anchor)
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src)
print('fixed: guard empty file buffer before calling the netrc scanner')
PY

# ---- 2. Rebuild incrementally so /app/src/src/curl reflects the fix. ----
( cd "$SRC" && make -j1 )

# ---- 3. Root-cause write-up. ----
cat > /app/diagnosis.md <<'MD'
# Diagnosis: curl crashes on a comment-only .netrc file

## Symptom

`curl --netrc --netrc-file <file> URL` dies with SIGSEGV (shell reports
"Segmentation fault", exit 139) as soon as `<file>` contains only comment
lines (or is an empty file). The process dies during startup, before any
request is sent, deterministically.

## Root cause

While a .netrc file is loaded, comment lines are skipped on the way in, so a
comment-only file leaves the in-memory buffer EMPTY after loading. The load
result is then handed to the scanner unconditionally. The scanner initialises
its tokenizer with the buffer's content pointer, which is NULL for an empty
buffer, and the tokenizer's very first step dereferences that NULL pointer
while skipping blanks / looking at the first byte of the "token" ->
instant, deterministic SIGSEGV. A file with real `machine` entries has
non-empty content and is unaffected.

## Fix

Before scanning, check whether the loaded buffer is empty and, if so, return
"no matching entry" immediately instead of feeding the empty buffer to the
scanner. No-match is already the ordinary outcome the callers handle for
credential files that contain nothing usable: the request proceeds with no
credentials (anonymous), exactly like a file that matches nothing.
MD

# ---- 4. Smoke: the reproducer must now succeed. ----
python3 - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'-foo-'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', 8890), H).serve_forever()
PY
srv=$!
trap 'kill $srv 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
    if ( exec 3<>/dev/tcp/127.0.0.1/8890 ) 2>/dev/null; then break; fi
    sleep 0.2
done

printf '# only a comment line' > /tmp/oracle_netrc
out=$(/app/src/src/curl --netrc --netrc-file /tmp/oracle_netrc http://127.0.0.1:8890/ 2>/tmp/oracle_err)
rc=$?
case "$out" in
  *-foo-*) ;;
  *) echo "oracle smoke: unexpected stdout: $out (rc=$rc)"; exit 1 ;;
esac
[ "$rc" -eq 0 ] || { echo "oracle smoke: rc=$rc"; cat /tmp/oracle_err; exit 1; }

# ---- 5. The project's own netrc tests must stay green. ----
( cd "$SRC" && cd tests && ./runtests.pl -n 1 2005 1304 >/tmp/oracle_tests.log 2>&1 )

echo "oracle done: fixed tree, rebuilt /app/src/src/curl, wrote /app/diagnosis.md"