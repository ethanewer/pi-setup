#!/bin/bash
# Oracle for opal-wave: write the tonegen.py program, then RUN it on the
# shipped spec to produce /app/calibration.wav. Never reads /tests.
set -euo pipefail

SOLVER="/app/tonegen.py"
OUT="/app/calibration.wav"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Multitone calibration-stimulus generator (opal-wave)."""
import json
import math
import random
import sys
import wave

import numpy as np


def synthesize(spec):
    sr = int(spec["sample_rate"])
    freqs = [float(f) for f in spec["frequencies"]]
    amps = [float(a) for a in spec["amplitudes"]]
    n = int(round(float(spec["duration_s"]) * sr))
    t = np.arange(n) / float(sr)
    s = np.zeros(n, dtype=float)
    for f, a in zip(freqs, amps):
        s += a * np.sin(2.0 * math.pi * f * t)
    if spec.get("dither"):
        rng = random.Random(int(spec["seed"]))
        d = np.array([rng.uniform(-0.5, 0.5) for _ in range(n)]) / 32768.0
        s = s + d
    target_rms = 10.0 ** (float(spec["target_rms_dbfs"]) / 20.0)
    rms = math.sqrt(float(np.mean(s * s)))
    s = s * (target_rms / rms)
    q = np.clip(np.round(s * 32768.0), -32768, 32767).astype("<i2")
    return q, sr


def main(argv):
    if len(argv) != 3:
        print("usage: tonegen.py <spec.json> <out.wav>", file=sys.stderr)
        return 2
    with open(argv[1], "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    q, sr = synthesize(spec)
    with wave.open(argv[2], "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(q.tobytes())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod +x "$SOLVER"

python3 "$SOLVER" /app/specs/main_spec.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
