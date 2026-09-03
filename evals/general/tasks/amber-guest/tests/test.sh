#!/bin/bash
#
# amber-guest verifier. Executes the deliverables
# /app/httpkit/multipart.py, /app/httpkit/chunked.py, /app/httpkit/cookies.py
# and /app/httpkit/request.py: import smoke, tamper detection on the
# shipped do-not-modify files (package init + visible fixtures), then three
# hidden probes that re-derive expected results from hidden inputs with
# independent reference implementations (multipart exact bytes, chunked
# decode + trailers + malformed streams, cookie-store scripted exchanges).
# Writes REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path
# (EXIT trap).
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "amber-guest verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverables present, non-empty, importable (executes each path).
# ---------------------------------------------------------------------------
for f in /app/httpkit/multipart.py /app/httpkit/chunked.py \
         /app/httpkit/cookies.py /app/httpkit/request.py; do
  if [ ! -s "$f" ]; then
    overall=0; msgs="$msgs missing-or-empty:$f"
  fi
done
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 60 python3 -c "
import sys; sys.path.insert(0, '/app')
import httpkit.multipart as m
import httpkit.chunked as c
import httpkit.cookies as k
import httpkit.request as r
assert callable(m.multipart_encode) and callable(m.make_boundary)
assert hasattr(c, 'ChunkedError') and callable(c.decode_chunked)
assert hasattr(k, 'CookieStore')
assert callable(r.build_request) and callable(r.parse_response)
print('import ok')
" >/tmp/dsk_import.log 2>&1; then
    overall=0; msgs="$msgs import:failed"
    tail -8 /tmp/dsk_import.log >&2 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 2. Tamper detection: do-not-modify shipped files stay pristine.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! cmp -s /app/httpkit/__init__.py /opt/pristine/httpkit__init__.py; then
    overall=0; msgs="$msgs tampered:httpkit/__init__.py"
  fi
  if ! diff -rq /app/fixtures /opt/pristine/fixtures >/dev/null 2>&1; then
    overall=0; msgs="$msgs tampered:fixtures"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Hidden probes (each recomputes expected results from hidden inputs).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  probes=0
  for p in /tests/hidden/probe_multipart/probe.py \
           /tests/hidden/probe_chunked/probe.py \
           /tests/hidden/probe_cookies/probe.py; do
    [ -f "$p" ] || continue
    probes=$((probes+1))
    if ! $TIMEOUT_CMD 90 python3 "$p" >/tmp/dsk_probe_$(basename $(dirname $p)).log 2>&1; then
      overall=0
      msgs="$msgs probe-failed:$(basename "$(dirname "$p")")"
      tail -12 /tmp/dsk_probe_$(basename $(dirname $p)).log >&2 2>/dev/null || true
    fi
  done
  [ "$probes" -ge 3 ] || { overall=0; msgs="$msgs no-hidden-probes"; }
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0