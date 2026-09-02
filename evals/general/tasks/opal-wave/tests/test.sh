#!/bin/bash
# Verifier for opal-wave: checks both deliverables, re-EXECUTES the deliverable
# program /app/tonegen.py on the shipped spec and on every hidden spec, and
# applies property checks (header, RMS band, tone presence/ratios, notch) to
# each produced WAV. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, math, os, subprocess, sys, wave

import numpy as np

SOLVE = "/app/tonegen.py"
failures = []


def check_wav(path, spec):
    """Property checks on a produced wav against its spec. Returns error list."""
    errs = []
    sr = int(spec["sample_rate"])
    freqs = [float(f) for f in spec["frequencies"]]
    amps = [float(a) for a in spec["amplitudes"]]
    n = int(round(float(spec["duration_s"]) * sr))
    target_rms = 10.0 ** (float(spec["target_rms_dbfs"]) / 20.0)
    try:
        w = wave.open(path, "rb")
        nch, sw, fr, nfr = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(nfr)
        w.close()
    except Exception as e:
        return ["%s: unreadable wav (%s)" % (path, e)]
    if nch != 1:
        errs.append("%s: not mono (%d ch)" % (path, nch))
    if sw != 2:
        errs.append("%s: not 16-bit (sampwidth %d)" % (path, sw))
    if fr != sr:
        errs.append("%s: sample rate %d != %d" % (path, fr, sr))
    if nfr != n:
        errs.append("%s: %d frames != %d" % (path, nfr, n))
    if errs:
        return errs
    x = np.frombuffer(raw, dtype="<i2").astype(float) / 32768.0
    rms = float(np.sqrt(np.mean(x * x)))
    if abs(rms - target_rms) > 0.02:
        errs.append("%s: rms %.4f outside band of %.4f" % (path, rms, target_rms))
    # windowed amplitude estimate at an arbitrary frequency
    idx = np.arange(n)
    win = 0.5 - 0.5 * np.cos(2.0 * np.pi * idx / n)
    xw = x * win
    wsum = float(np.sum(win))

    def amp_at(f):
        e = np.exp(-2j * np.pi * f * idx / sr)
        return 2.0 * float(np.abs(np.dot(xw, e))) / wsum

    denom = math.sqrt(sum(a * a for a in amps) / 2.0)
    expected = [target_rms * a / denom for a in amps]
    est = [amp_at(f) for f in freqs]
    biggest = max(expected)
    for f, a, e in zip(freqs, est, expected):
        if not (0.5 * e <= a <= 2.0 * e):
            errs.append("%s: tone %.1f Hz amplitude %.5f not consistent with expected %.5f"
                        % (path, f, a, e))
    notch = spec.get("notch_hz")
    if notch is not None:
        na = amp_at(float(notch))
        if na > 0.05 * biggest:
            errs.append("%s: spur at notch %.1f Hz (%.5f)" % (path, float(notch), na))
    return errs


def run_case(spec_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run([sys.executable, SOLVE, spec_path, out_path],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        return ["tonegen.py failed to run (%s)" % e]
    if r.returncode != 0:
        return ["tonegen.py rc=%d stderr=%s" % (r.returncode, r.stderr[-300:])]
    if not os.path.exists(out_path):
        return ["tonegen.py produced no output for %s" % spec_path]
    try:
        with open(spec_path) as fh:
            spec = json.load(fh)
    except Exception as e:
        return ["spec %s unreadable (%s)" % (spec_path, e)]
    return check_wav(out_path, spec)


if not os.path.isfile(SOLVE):
    failures.append("missing /app/tonegen.py")
else:
    # visible deliverable: /app/calibration.wav must exist and match the
    # shipped spec's property checks
    if not os.path.isfile("/app/specs/main_spec.json"):
        failures.append("shipped spec missing")
    else:
        if os.path.isfile("/app/calibration.wav"):
            try:
                with open("/app/specs/main_spec.json") as fh:
                    spec = json.load(fh)
                failures.extend(check_wav("/app/calibration.wav", spec))
            except Exception as e:
                failures.append("calibration.wav check error (%s)" % e)
        else:
            failures.append("missing /app/calibration.wav")
        # re-execute the deliverable on the shipped spec
        failures.extend(run_case("/app/specs/main_spec.json", "/tmp/opal_wave_vis.wav"))

    # hidden cases: execute the deliverable on fresh specs
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            spec = os.path.join(hidden_dir, c, "spec.json")
            if not os.path.isfile(spec):
                failures.append("hidden '%s' malformed" % c)
                continue
            failures.extend(run_case(spec, "/tmp/opal_wave_%s.wav" % c))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
