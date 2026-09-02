#!/usr/bin/env python3
"""zephyr-cipher reference solver.

Usage: python3 solve.py <input_dir> <output_dir>

Reads the scenario in <input_dir> (STFT signal+params, localized-decimal
spectrum file, multitone parameters, and a speech mp3), performs the five
signal-processing recovery tasks, and writes <output_dir>/answer.json plus a
16-bit wav and a magnitude CSV.

This is the reference program the reference solution installs and runs; an
agent must produce an equivalent /app/solve.py.
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from scipy import signal as sig


def read_scenario(inp):
    """Return (stft_params, spec_x_wn_cache...) handled per-task below."""
    return inp


def parse_spectrum(path):
    """Parse a nonstandard delimited spectrum file.

    Format: two columns separated by ';', decimal separator is ',' (localized),
    an optional header line, free whitespace allowed. Returns (x, y) floats.
    """
    xs, ys = [], []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            left, _, right = line.partition(";")
            if not right:
                continue  # header / malformed
            try:
                x = float(left.strip().replace(",", "."))
                y = float(right.strip().replace(",", "."))
            except ValueError:
                continue
            xs.append(x)
            ys.append(y)
    return np.asarray(xs, dtype=float), np.asarray(ys, dtype=float)


def main():
    if len(sys.argv) != 3:
        print("usage: solve.py <input_dir> <output_dir>", file=sys.stderr)
        sys.exit(2)
    inp = sys.argv[1]
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)

    ans = {}

    # ---- 1) STFT magnitudes ----
    params = json.load(open(os.path.join(inp, "stft_params.json")))
    signal = np.load(os.path.join(inp, "stft_signal.npy"))
    f, t, Zxx = sig.stft(
        signal,
        fs=params["fs"],
        window=params["window"],
        nperseg=params["nperseg"],
        noverlap=params["noverlap"],
        nfft=params["nfft"],
        return_onesided=params["one_sided"],
        boundary=params["boundary"],
    )
    mag = np.abs(Zxx)  # linear magnitude, shape (nfreq, nframes)
    # per-frame rows, per-bin columns
    ans["stft_mag"] = mag.T.tolist()
    csv_path = os.path.join(out, "stft_mag.csv")
    with open(csv_path, "w") as fh:
        for row in mag.T:
            fh.write(",".join("%.9g" % v for v in row) + "\n")
    ans["stft_mag_csv"] = os.path.basename(csv_path)
    ans["stft_freqs"] = f.tolist()
    ans["stft_frames_s"] = t.tolist()

    # ---- 2 & 3) parse localized-decimal spectrum + wavelength -> wavenumber ----
    x_nm, y = parse_spectrum(os.path.join(inp, "spectrum.txt"))
    ans["spec_x"] = x_nm.tolist()
    ans["spec_y"] = y.tolist()
    # wavelength (nm) -> wavenumber (cm^-1) : wn = 1e7 / wavelength_nm
    wn = 1e7 / x_nm
    # peaks: local maxima of intensity
    peaks_cm1 = []
    for i in range(1, len(y) - 1):
        if y[i] > y[i - 1] and y[i] > y[i + 1]:
            peaks_cm1.append(1e7 / x_nm[i])
    ans["wavenumber_peaks_cm1"] = sorted(peaks_cm1)

    # ---- 4) multitone synthesis + RMS normalize + 16-bit wav ----
    tpar = json.load(open(os.path.join(inp, "tone.json")))
    sr = tpar["sample_rate"]
    n = int(round(tpar["duration_s"] * sr))
    tt = np.arange(n) / sr
    s = np.zeros(n)
    for fi, ai in zip(tpar["frequencies"], tpar["amplitudes"]):
        s = s + ai * np.sin(2 * np.pi * fi * tt)
    if tpar.get("dither", True):
        rng = np.random.default_rng(tpar.get("seed", 0))
        s = s + rng.uniform(-0.5, 0.5, n) * (1.0 / 32768.0)
    rms = np.sqrt(np.mean(s ** 2))
    if rms > 0:
        s = s * (tpar["target_rms"] / rms)
    pcm = np.clip(np.round(s * 32767.0), -32768, 32767).astype("<i2")
    wav_name = "tone.wav"
    wav_path = os.path.join(out, wav_name)
    import wave
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    ans["tone_wav"] = wav_name

    # ---- 5) speech-only transcription (mp3 -> 16k PCM -> vosk) ----
    import vosk
    mp3 = os.path.join(inp, "speech.mp3")
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", mp3, "-f", "s16le",
         "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", "-"],
        capture_output=True, check=True,
    ).stdout
    model = vosk.Model("/opt/vosk/vosk-model-small-en-us-0.15")
    rec = vosk.KaldiRecognizer(model, 16000)
    rec.AcceptWaveform(raw)
    text = json.loads(rec.FinalResult()).get("text", "")
    ans["transcript"] = text

    with open(os.path.join(out, "answer.json"), "w") as fh:
        json.dump(ans, fh, indent=1)
    print("wrote", os.path.join(out, "answer.json"))


if __name__ == "__main__":
    main()
