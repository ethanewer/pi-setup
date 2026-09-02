# Hearing-screen calibration tone generator

An audiology lab needs a small, reusable program that turns a JSON tone
specification into a calibrated multitone test stimulus: a mono 16 kHz
16-bit PCM WAV file plus a short measurement report. You must write the
program and run it on the shipped specification.

## Working directory

Everything runs from `/app`. Python 3.12 is available as `python3`; the only
third-party package installed (or permitted) is `numpy`. Use the
standard-library `wave` module for the WAV file. Do not modify the shipped
specification file.

## Deliverables (all three required)

1. `/app/solve.py` — a runnable Python program:
   ```
   python3 /app/solve.py <spec.json> <out_wav> <out_report.json>
   ```
   It must work on **any** spec file conforming to the format below — the
   grader re-runs it on unseen specifications, so hard-coding the shipped
   values or paths is not acceptable.

2. `/app/tone.wav` — the stimulus your program produces when run as:
   ```
   python3 /app/solve.py /app/tone_spec.json /app/tone.wav /app/report.json
   ```

3. `/app/report.json` — the measurement report produced by the same run.

## Spec format

`<spec.json>` is a JSON object with exactly these keys:

```json
{
  "frequencies":  [440.0, 1320.0],   // tone frequencies in Hz, all < sample_rate/2
  "amplitudes":   [1.0, 0.5],        // relative amplitudes, same length, all > 0
  "phase_deg":    [0.0, 90.0],       // per-tone initial phase in degrees
  "duration_ms":  400,               // integer duration in milliseconds
  "sample_rate":  16000,             // samples per second (always 16000 here)
  "target_rms":   0.3,               // post-normalization RMS level, 0 < target <= 0.9
  "dither":       true,              // whether to add seeded uniform dither
  "seed":         42                 // RNG seed for the dither
}
```

## Synthesis algorithm (implement it exactly)

1. `n = int(round(duration_ms * sample_rate / 1000))` samples;
   `t = arange(n) / sample_rate`.
2. `s = sum_k amplitudes[k] * sin(2*pi*frequencies[k]*t + radians(phase_deg[k]))`
   summed over all k.
3. If `dither` is true, add uniform dither of one quantization step:
   draw `n` values `u` with `numpy.random.default_rng(seed)` via
   `rng.uniform(-0.5/32768.0, 0.5/32768.0, n)` and add them to `s`.
4. RMS-normalize: compute `rms = sqrt(mean(s**2))` and scale
   `s = s * (target_rms / rms)`. (A spec whose synthesis is identically zero
   cannot be normalized: the program must print an error to stderr and exit
   non-zero in that case.)
5. Quantize to 16-bit PCM: `y = clip(round(s * 32767), -32768, 32767)`
   stored as little-endian int16.
6. Write a **mono, 16-bit, sample_rate-Hz** WAV with the standard 44-byte
   header (standard-library `wave`, no extra chunks) to `<out_wav>`.
7. Write the report JSON to `<out_report.json>` with exactly these keys:
   ```json
   {
     "n_samples": <int>,       // number of samples in the wav
     "sample_rate": <int>,
     "rms": <float>,           // RMS of the DECODED quantized samples (y/32768.0)
     "peak_freqs": [ ... ]     // spec frequencies, sorted ascending
   }
   ```

The program must be deterministic: with the same spec it must produce
byte-identical WAV files on repeated runs (the dither is seeded, so this is
automatic if you follow step 3).

## Edge cases the grader probes

- A single-tone spec and multi-tone specs (up to five tones), with
  non-zero phase offsets and unequal amplitudes.
- Tones close to the Nyquist limit (e.g. 7500 Hz at 16 kHz) must still
  produce a detectable spectral peak.
- Very short stimuli (tens of milliseconds).
- `dither: false` (no RNG draw at all) and `dither: true`.
- Small target levels (e.g. 0.05).
- A degenerate spec (e.g. all amplitudes zero, or a missing required key)
  must make the program exit **non-zero** with a message on stderr — never
  write a bogus wav silently.

## Grading

The grader re-executes `/app/solve.py` on the shipped spec and on several
hidden specs. For each normal case it checks the WAV header (mono, 16-bit,
sample rate, exact sample count), that the decoded RMS is within ±0.015 of
`target_rms`, that a clear spectral peak exists at every requested
frequency, and that the report agrees with the wav. For degenerate specs it
requires a non-zero exit. It also re-runs one case twice and requires
byte-identical wavs.
