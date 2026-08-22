#!/usr/bin/env bash
# Render scene B (harbor-night). Prints one line per rendered frame.
set -euo pipefail
SEED="${SEED:-0}"
read -r DUR SUM <<< "$(python3 - "$SEED" <<'EOF'
import hashlib, random, sys
r = random.Random(f"{sys.argv[1]}:t5:b")
print(r.randint(90, 200), hashlib.sha256(f"{sys.argv[1]}:t5:b:sum".encode()).hexdigest()[:10])
EOF
)"
echo "[render_b] scene: harbor-night, 1080p, path-traced"
TOTAL=$((DUR / 3))
END=$((SECONDS + DUR))
frame=0
while (( SECONDS < END )); do
  frame=$((frame + 1))
  echo "[render_b] rendered frame $frame/$TOTAL"
  sleep 3
done
echo "RENDER_B COMPLETE checksum=$SUM"
