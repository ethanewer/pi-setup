#!/usr/bin/env bash
# Render scene A (dawn-city). Prints one line per rendered frame.
set -euo pipefail
SEED="${SEED:-0}"
read -r DUR SUM <<< "$(python3 - "$SEED" <<'EOF'
import hashlib, random, sys
r = random.Random(f"{sys.argv[1]}:t5:a")
print(r.randint(60, 140), hashlib.sha256(f"{sys.argv[1]}:t5:a:sum".encode()).hexdigest()[:10])
EOF
)"
echo "[render_a] scene: dawn-city, 1080p, path-traced"
TOTAL=$((DUR / 3))
END=$((SECONDS + DUR))
frame=0
while (( SECONDS < END )); do
  frame=$((frame + 1))
  echo "[render_a] rendered frame $frame/$TOTAL"
  sleep 3
done
echo "RENDER_A COMPLETE checksum=$SUM"
printf '{"checksum": "%s", "elapsed": %s, "pid": %s, "nonce": "%s", "seed": "%s"}\n' \
  "$SUM" "$SECONDS" "$$" "${MB_NONCE:-}" "$SEED" > render_a.done
