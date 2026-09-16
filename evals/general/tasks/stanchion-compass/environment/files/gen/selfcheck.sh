#!/bin/bash
# Build-time selfcheck: prove the SHIPPED app is in the "one enormous entry
# bundle" state the task describes: single JS chunk, well over the byte
# budget, all three heavy modules inside it.
set -eu
cd /app
npm run build > /tmp/sc-selfcheck.log 2>&1 || {
  echo "selfcheck: build failed" >&2
  tail -30 /tmp/sc-selfcheck.log >&2
  exit 1
}

count=$(ls dist/assets/*.js 2>/dev/null | wc -l)
if [ "$count" -ne 1 ]; then
  echo "selfcheck: expected exactly 1 JS chunk in the shipped build, got $count" >&2
  ls -la dist/assets >&2
  exit 1
fi

size=$(stat -c%s dist/assets/*.js)
if [ "$size" -le 400000 ]; then
  echo "selfcheck: shipped entry is only $size bytes; task requires > 400000" >&2
  exit 1
fi

entry=$(ls dist/assets/*.js)
for marker in sc_mk_9f31_charts sc_mk_d20a_reports sc_mk_73b4_admin; do
  grep -q "$marker" "$entry" || {
    echo "selfcheck: marker $marker missing from shipped entry" >&2
    exit 1
  }
done

echo "selfcheck: shipped naive shape confirmed (single $size-byte entry with all heavy routes)"
rm -rf /app/dist
echo "selfcheck: dist cleaned; agent and verifier will rebuild"