#!/bin/bash
# Oracle for opal-quill: write the tone-generator program, then RUN it on the
# shipped spec to produce the /app/tone.wav + /app/report.json deliverables.
# Never reads /tests.
set -eu

SOLVER="/app/solve.py"

cat > "$SOLVER" <<'PY'
import json
import sys
import wave

import numpy as np

REQUIRED = ["frequencies", "amplitudes", "phase_deg", "duration_ms",
            "sample_rate", "target_rms", "dither", "seed"]


def die(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(1)


def main():
    if len(sys.argv) != 4:
        die("usage: solve.py <spec.json> <out_wav> <out_report.json>")
    spec_path, wav_path, report_path = sys.argv[1:4]

    try:
        with open(spec_path, "r", encoding="utf-8") as fh:
            spec = json.load(fh)
    except Exception as exc:
        die("cannot read spec: %s" % exc)

    if not isinstance(spec, dict):
        die("spec must be a JSON object")
    for key in REQUIRED:
        if key not in spec:
            die("spec missing required key %r" % key)

    freqs = [float(f) for f in spec["frequencies"]]
    amps = [float(a) for a in spec["amplitudes"]]
    phases = [float(p) for p in spec["phase_deg"]]
    if not (len(freqs) == len(amps) == len(phases)):
        die("frequencies/amplitudes/phase_deg must have equal length")
    if not freqs:
        die("spec has no tones")
    if any(a <= 0.0 for a in amps):
        die("all amplitudes must be > 0")
    sr = int(spec["sample_rate"])
    dur_ms = int(spec["duration_ms"])
    target = float(spec["target_rms"])
    if sr <= 0 or dur_ms <= 0:
        die("sample_rate and duration_ms must be positive")
    if not (0.0 < target <= 0.9):
        die("target_rms must be in (0, 0.9]")
    if any(f <= 0.0 or f >= sr / 2.0 for f in freqs):
        die("every frequency must lie strictly inside (0, sample_rate/2)")

    n = int(round(dur_ms * sr / 1000))
    t = np.arange(n, dtype=np.float64) / float(sr)
    s = np.zeros(n, dtype=np.float64)
    for f, a, p in zip(freqs, amps, phases):
        s += a * np.sin(2.0 * np.pi * f * t + np.radians(p))

    if spec["dither"]:
        rng = np.random.default_rng(int(spec["seed"]))
        s += rng.uniform(-0.5 / 32768.0, 0.5 / 32768.0, n)

    rms = float(np.sqrt(np.mean(s ** 2)))
    if rms <= 0.0:
        die("synthesized signal is identically zero; cannot normalize")
    s = s * (target / rms)

    y = np.clip(np.round(s * 32767.0), -32768, 32767).astype("<i2")

    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(y.tobytes())

    decoded = y.astype(np.float64) / 32768.0
    dec_rms = float(np.sqrt(np.mean(decoded ** 2)))
    report = {
        "n_samples": int(n),
        "sample_rate": sr,
        "rms": dec_rms,
        "peak_freqs": sorted(freqs),
    }
    with open(report_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/tone_spec.json /app/tone.wav /app/report.json

echo "solve.sh done"
ls -l "$SOLVER" /app/tone.wav /app/report.json
