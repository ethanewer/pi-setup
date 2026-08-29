#!/bin/bash
# Verifier for zephyr-cipher (executes-deliverable). Re-runs /app/solve.py on
# the visible scenario and on every hidden case, and checks each of the five
# competencies against an independent gold: STFT magnitudes (scipy.stft),
# localized-decimal spectrum parse + wavelength->wavenumber peaks, the
# synthesized/normalized 16-bit wav (header, RMS, spectral tones), and the
# speech transcript.
# Writes reward to /logs/verifier/reward.txt (1 all pass, 0 otherwise).
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, re, shutil, subprocess, sys
import numpy as np
from scipy import signal as sig

SOL = "/app/solve.py"
failures = []

def fail(m):
    failures.append(m)

def check(c, m):
    if not c:
        fail(m)

check(os.path.exists(SOL), "missing deliverable /app/solve.py")

def norm(t):
    return re.sub(r'[^a-z0-9]+', '', (t or '').lower())

# ---------- independent gold computations ----------
def gold_stft(inp):
    p = json.load(open(os.path.join(inp, "stft_params.json")))
    x = np.load(os.path.join(inp, "stft_signal.npy"))
    f, t, Z = sig.stft(x, fs=p["fs"], window=p["window"], nperseg=p["nperseg"],
                       noverlap=p["noverlap"], nfft=p["nfft"],
                       return_onesided=p["one_sided"], boundary=p["boundary"])
    return np.abs(Z)  # (nfreq, nframes) linear magnitude

def parse_spec(path):
    xs, ys = [], []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        left, _, right = line.partition(";")
        if not right:
            continue
        try:
            xs.append(float(left.strip().replace(",", ".")))
            ys.append(float(right.strip().replace(",", ".")))
        except ValueError:
            continue
    return np.asarray(xs), np.asarray(ys)

def gold_peaks(inp):
    x, y = parse_spec(os.path.join(inp, "spectrum.txt"))
    peaks = []
    for i in range(1, len(y) - 1):
        if y[i] > y[i - 1] and y[i] > y[i + 1]:
            peaks.append(1e7 / x[i])
    return sorted(peaks)

def check_wav(inp, outdir, wavname):
    tp = json.load(open(os.path.join(inp, "tone.json")))
    path = os.path.join(outdir, wavname)
    if not os.path.exists(path):
        return [wavname + " missing"]
    errs = []
    import wave
    w = wave.open(path, "rb")
    nch = w.getnchannels(); sw = w.getsampwidth()
    sr = w.getframerate(); nfr = w.getnframes()
    if nch != 1:
        errs.append(wavname + " not mono")
    if sw != 2:
        errs.append(wavname + " not 16-bit")
    if sr != tp["sample_rate"]:
        errs.append(wavname + " sample rate %d != %d" % (sr, tp["sample_rate"]))
    data = np.frombuffer(w.readframes(nfr), dtype="<i2").astype(float) / 32768.0
    w.close()
    exp_n = int(round(tp["duration_s"] * tp["sample_rate"]))
    if abs(nfr - exp_n) > 2:
        errs.append(wavname + " length %d != ~%d" % (nfr, exp_n))
    rms = float(np.sqrt(np.mean(data ** 2)))
    if abs(rms - tp["target_rms"]) > 0.02:
        errs.append(wavname + " rms %.4f not within band of %.4f" % (rms, tp["target_rms"]))
    X = np.abs(np.fft.rfft(data, n=2 ** 16))
    fx = np.fft.rfftfreq(2 ** 16, 1.0 / tp["sample_rate"])
    for fq in tp["frequencies"]:
        k = int(round(fq / fx[1]))
        if X[k] < 0.12 * X.max():
            errs.append(wavname + " missing tone at %.2f Hz" % fq)
    return errs

def check_case(inp, outdir, expected):
    errs = []
    subprocess.run(["python3", SOL, inp, outdir], capture_output=True)
    ap = os.path.join(outdir, "answer.json")
    if not os.path.exists(ap):
        return [inp + ": no answer.json"]
    a = json.load(open(ap))
    # STFT magnitudes
    gm = gold_stft(inp)
    ag = np.asarray(a["stft_mag"]).T
    if ag.shape != gm.shape:
        errs.append("%s: stft shape %s != %s" % (inp, ag.shape, gm.shape))
    elif not np.allclose(ag, gm, atol=1e-4, rtol=1e-4):
        errs.append("%s: stft magnitudes differ from gold" % inp)
    # CSV export exists (per-frame rows, per-bin columns)
    if not os.path.exists(os.path.join(outdir, "stft_mag.csv")):
        errs.append("%s: stft_mag.csv missing" % inp)
    # spectrum parse round-trip + wavenumber peaks
    gx, gy = parse_spec(os.path.join(inp, "spectrum.txt"))
    ax = np.asarray(a.get("spec_x", [])); ay = np.asarray(a.get("spec_y", []))
    if ax.shape != gx.shape or ay.shape != gy.shape:
        errs.append("%s: parsed spectrum shape mismatch" % inp)
    elif not (np.allclose(ax, gx, atol=1e-4, rtol=1e-6)
              and np.allclose(ay, gy, atol=1e-4, rtol=1e-6)):
        errs.append("%s: parsed spectrum values differ" % inp)
    gp = gold_peaks(inp)
    apk = sorted(a.get("wavenumber_peaks_cm1", []))
    if len(apk) != len(gp) or not np.allclose(apk, gp, atol=1.0):
        errs.append("%s: wavenumber peaks %s != %s" % (inp, apk, gp))
    # wav
    if not a.get("tone_wav"):
        errs.append("%s: no tone_wav entry" % inp)
    else:
        errs += check_wav(inp, outdir, a["tone_wav"])
    # transcript
    if expected is not None:
        want = norm(expected.get("transcript", ""))
        got = norm(a.get("transcript", ""))
        if want != got:
            errs.append("%s: transcript %r != %r" % (inp, a.get("transcript"), expected.get("transcript")))
        elif not got:
            errs.append("%s: empty transcript" % inp)
    return errs

# ---------- 1) visible case ----------
expected_vis = None
if os.path.exists('/tests/expected.json'):
    expected_vis = json.load(open('/tests/expected.json'))
errs = check_case('/app/scenario', '/tmp/visout', expected_vis)
for e in errs:
    fail('visible: ' + e)

# /app/answer.json deliverable (produced by the oracle running solve.py)
if os.path.exists('/app/answer.json') and expected_vis is not None:
    try:
        ap = json.load(open('/app/answer.json'))
        if norm(ap.get("transcript")) != norm(expected_vis.get("transcript")):
            fail('deliverable /app/answer.json transcript mismatch')
    except Exception as ex:
        fail('deliverable /app/answer.json: ' + str(ex))
else:
    fail('missing deliverable /app/answer.json')

# ---------- 2) hidden cases ----------
hidden = '/tests/hidden'
cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
check(len(cases) >= 2, 'expected >=2 hidden cases')
for case in cases:
    src = os.path.join(hidden, case)
    if not os.path.isdir(src):
        continue
    ep = os.path.join(src, 'expected.json')
    if not os.path.exists(ep):
        fail('%s: no expected.json' % case); continue
    expected = json.load(open(ep))
    work = '/tmp/hc/%s' % case
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work, exist_ok=True)
    errs = check_case(src, work, expected)
    for e in errs:
        fail('%s: %s' % (case, e))

if failures:
    print('FAILURES:')
    for m in failures:
        print('  - ' + m)
    open('/logs/verifier/reward.txt', 'w').write('0')
    sys.exit(0)
open('/logs/verifier/reward.txt', 'w').write('1')
print('ALL PASS')
sys.exit(0)
PY
