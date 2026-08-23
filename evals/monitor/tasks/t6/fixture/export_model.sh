#!/usr/bin/env bash
# Model export job: renders ONLY a progress bar (no lines) until it finishes.
set -euo pipefail
SEED="${SEED:-0}"
DUR=$(python3 -c "import random; print(random.Random('${SEED}:t6:export').randint(150, 210))")
NONCE="${MB_NONCE:-}"
ARTIFACT="model-${NONCE}.bin"
python3 - "$DUR" "$ARTIFACT" <<'PY'
import sys, time
dur = int(sys.argv[1]); artifact = sys.argv[2]
start = time.time()
while True:
    frac = min(1.0, (time.time() - start) / dur)
    bar = "#" * int(40 * frac)
    sys.stdout.write(f"\rexporting: [{bar:<40}] {int(frac * 100)}%")
    sys.stdout.flush()
    if frac >= 1.0:
        break
    time.sleep(0.5)
with open(artifact, "wb") as f:
    f.write(b"0" * 1024)
print()
print(f"EXPORT COMPLETE artifact={artifact} bytes=1024")
PY
printf '{"artifact": "%s", "elapsed": %s, "nonce": "%s", "seed": "%s"}\n' \
  "$ARTIFACT" "$SECONDS" "$NONCE" "$SEED" > export_done.json
