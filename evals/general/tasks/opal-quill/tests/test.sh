#!/bin/bash
# Verifier for opal-quill (executes-deliverable): re-executes /app/solve.py on
# the shipped spec and on every hidden case, checks the 16-bit wav header, the
# RMS band, spectral peaks, the report, determinism, and degenerate-spec
# handling. Writes 1/0 to /logs/verifier/reward.txt. Never crashes on
# malformed agent output: every parse is guarded and reward is always written.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import subprocess
import sys
import wave

import numpy as np

SOLVER = "/app/solve.py"
VISIBLE_SPEC = "/app/tone_spec.json"
VISIBLE_WAV = "/app/tone.wav"
VISIBLE_REPORT = "/app/report.json"
failures = []


def fail(msg):
    failures.append(msg)


def run_solver(spec, wav, report):
    try:
        return subprocess.run(
            [sys.executable, SOLVER, spec, wav, report],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        fail("solver crashed running %s: %r" % (spec, exc))
        return None


def read_wav(path):
    """Return (nch, sampwidth, rate, float samples in [-1,1)) or None."""
    try:
        with wave.open(path, "rb") as w:
            nch = w.getnchannels()
            sw = w.getsampwidth()
            sr = w.getframerate()
            nfr = w.getnframes()
            raw = w.readframes(nfr)
        if sw != 2:
            fail("%s: expected 16-bit samples, got sampwidth=%d" % (path, sw))
            return None
        data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
        return nch, sr, nfr, data
    except Exception as exc:
        fail("%s: unreadable wav (%r)" % (path, exc))
        return None


def property_checks(tag, spec, wav_path, report_path):
    p = read_wav(wav_path)
    if p is None:
        fail("%s: wav missing/unreadable" % tag)
        return
    nch, sr, nfr, data = p
    sr_spec = int(spec["sample_rate"])
    n_exp = int(round(int(spec["duration_ms"]) * sr_spec / 1000))
    if nch != 1:
        fail("%s: wav not mono (channels=%d)" % (tag, nch))
    if sr != sr_spec:
        fail("%s: sample rate %d != %d" % (tag, sr, sr_spec))
    if abs(nfr - n_exp) > 1:
        fail("%s: frame count %d != %d" % (tag, nfr, n_exp))
    if data.size != nfr:
        fail("%s: truncated wav data" % tag)
        return

    target = float(spec["target_rms"])
    rms = float(np.sqrt(np.mean(data ** 2))) if data.size else 0.0
    if abs(rms - target) > 0.015:
        fail("%s: rms %.4f outside band around target %.4f" % (tag, rms, target))

    # spectral peaks at every requested frequency
    freqs = [float(f) for f in spec["frequencies"]]
    nfft = 1 << 18
    X = np.abs(np.fft.rfft(data, n=nfft))
    df = sr_spec / nfft
    for f in freqs:
        k = int(round(f / df))
        if k <= 0 or k >= X.size:
            fail("%s: frequency %.1f Hz out of FFT range" % (tag, f))
            continue
        if X[k] < 0.15 * float(X.max()):
            fail("%s: missing spectral peak at %.1f Hz" % (tag, f))

    # report agreement
    try:
        with open(report_path) as fh:
            rep = json.load(fh)
    except Exception as exc:
        fail("%s: report unreadable (%r)" % (tag, exc))
        return
    if not isinstance(rep, dict):
        fail("%s: report is not a JSON object" % tag)
        return
    if rep.get("n_samples") != nfr:
        fail("%s: report n_samples %r != %d" % (tag, rep.get("n_samples"), nfr))
    if rep.get("sample_rate") != sr_spec:
        fail("%s: report sample_rate %r != %d" % (tag, rep.get("sample_rate"), sr_spec))
    rep_rms = rep.get("rms")
    if not isinstance(rep_rms, (int, float)) or abs(float(rep_rms) - rms) > 0.005:
        fail("%s: report rms %r != decoded %.5f" % (tag, rep_rms, rms))
    pf = rep.get("peak_freqs")
    if not isinstance(pf, list) or len(pf) != len(freqs) or any(
            not isinstance(a, (int, float)) or not isinstance(b, (int, float))
            or abs(float(a) - float(b)) > 1e-6
            for a, b in zip(sorted(pf), sorted(freqs))):
        fail("%s: report peak_freqs %r != sorted spec freqs" % (tag, pf))


# ---- 1. deliverable exists -------------------------------------------------
if not os.path.isfile(SOLVER):
    fail("missing /app/solve.py")

# ---- 2. visible case: execute on the shipped spec ---------------------------
if os.path.isfile(SOLVER) and os.path.isfile(VISIBLE_SPEC):
    out1, rep1 = "/tmp/vis1.wav", "/tmp/vis1.json"
    for p in (out1, rep1):
        if os.path.exists(p):
            os.remove(p)
    r = run_solver(VISIBLE_SPEC, out1, rep1)
    if r is None or r.returncode != 0:
        fail("visible case: solver exited %s (%s)"
             % (r.returncode if r else "?", (r.stderr[-200:] if r else "")))
    else:
        property_checks("visible", json.load(open(VISIBLE_SPEC)), out1, rep1)
        # deliverables /app/tone.wav + /app/report.json must equal a fresh run
        if not os.path.isfile(VISIBLE_WAV):
            fail("missing /app/tone.wav")
        elif open(VISIBLE_WAV, "rb").read() != open(out1, "rb").read():
            fail("/app/tone.wav differs from a fresh run on the shipped spec")
        try:
            with open(VISIBLE_REPORT) as fh:
                art = json.load(fh)
            with open(rep1) as fh:
                fresh = json.load(fh)
            if art != fresh:
                fail("/app/report.json differs from a fresh run")
        except Exception as exc:
            fail("/app/report.json unreadable (%r)" % exc)
        # determinism: second run must give byte-identical wav
        out2 = "/tmp/vis2.wav"
        r2 = run_solver(VISIBLE_SPEC, out2, "/tmp/vis2.json")
        if r2 is None or r2.returncode != 0:
            fail("determinism re-run failed")
        elif open(out1, "rb").read() != open(out2, "rb").read():
            fail("repeated runs produced different wav bytes")

# ---- 3. hidden cases --------------------------------------------------------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        fail("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden_dir, case)
        spec_path = os.path.join(base, "spec.json")
        exp_path = os.path.join(base, "expected.json")
        if not (os.path.isfile(spec_path) and os.path.isfile(exp_path)):
            fail("hidden '%s': missing spec/expected" % case)
            continue
        try:
            spec = json.load(open(spec_path))
            exp = json.load(open(exp_path))
        except Exception as exc:
            fail("hidden '%s': unreadable fixtures (%r)" % (case, exc))
            continue
        if not isinstance(exp, dict):
            fail("hidden '%s': bad expected.json" % case)
            continue
        out = "/tmp/h_%s.wav" % case
        rep = "/tmp/h_%s.json" % case
        for p in (out, rep):
            if os.path.exists(p):
                os.remove(p)
        r = run_solver(spec_path, out, rep)
        if exp.get("expect_error"):
            if r is None or r.returncode == 0:
                fail("hidden '%s': expected non-zero exit for degenerate spec" % case)
            elif os.path.exists(out):
                fail("hidden '%s': wrote a wav despite degenerate spec" % case)
        else:
            if r is None or r.returncode != 0:
                fail("hidden '%s': solver exited %s"
                     % (case, r.returncode if r else "?"))
            else:
                property_checks("hidden:%s" % case, spec, out, rep)
else:
    fail("missing /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
exit 0
