# Synthesize a calibration multitone wav for a hearing-aid test bench

You are working on the signal-generation bench of a hearing-aid calibration
lab. The bench produces reference multitone stimuli as 16-bit WAV files: a
sum of fixed sines, optionally dithered, RMS-normalized to a requested level,
then quantized. You must write **one reusable program** and use it to produce
the shipped calibration file.

## Deliverables (both required)

1. `/app/tonegen.py` — a runnable Python program with this interface:

   ```
   python3 /app/tonegen.py <spec.json> <out.wav>
   ```

   It reads a synthesis spec (JSON, format below) and writes a mono 16-bit
   PCM WAV file at `<out.wav>`. It must work on **any** spec conforming to
   the contract below — the grader re-runs it on unseen specs.

2. `/app/calibration.wav` — the WAV your program produces **when run on the
   provided `/app/specs/main_spec.json`**:

   ```
   python3 /app/tonegen.py /app/specs/main_spec.json /app/calibration.wav
   ```

## Spec format (`spec.json`)

```json
{
  "frequencies":     [500.0, 1000.0, 1500.0],  // Hz, one entry per tone
  "amplitudes":      [1.0, 0.6, 0.4],          // relative amplitudes, same length
  "duration_s":      1.0,                      // seconds
  "sample_rate":     16000,                    // Hz (integer)
  "target_rms_dbfs": -10.0,                    // target RMS level in dBFS
  "dither":          true,                     // whether to add dither
  "seed":            42,                       // RNG seed for dither
  "notch_hz":        50.0                      // frequency that must stay silent, or null
}
```

## Synthesis contract (exact)

1. `n = int(round(duration_s * sample_rate))` samples; time axis
   `t = arange(n) / sample_rate`.
2. Signal `s = sum_i a_i * sin(2*pi*f_i*t)` over all `(frequencies[i],
   amplitudes[i])` pairs — all sines start at phase zero.
3. If `dither` is true, add uniform dither: draw `n` values
   `u_k ~ uniform(-0.5, 0.5)` from `random.Random(seed)` (drawn in index
   order) and add `u_k / 32768.0` to sample `k`. If `dither` is false, add
   nothing.
4. RMS-normalize: scale `s` by `target_rms / rms(s)` where
   `target_rms = 10^(target_rms_dbfs / 20)` and `rms(s)` is computed on the
   dithered signal.
5. Quantize: `q = clip(round(s * 32768), -32768, 32767)` as 16-bit signed
   integers (little-endian).
6. Write a **mono, 16-bit, `sample_rate`-Hz** WAV using the standard-library
   `wave` module with the standard 44-byte header (no extra chunks).

## What the grader checks (property checks)

The grader re-runs `/app/tonegen.py` on the shipped spec and on several
hidden specs, decodes each produced WAV, and requires:

- WAV header: mono, 16-bit PCM, correct sample rate, exactly `n` frames.
- Decoded RMS within **±0.02** of `target_rms = 10^(target_rms_dbfs/20)`.
- A spectral component at **every** listed frequency with amplitude
  consistent with its relative `amplitudes` entry (well-separated tones, so
  a windowed Goertzel/FFT estimate is unambiguous).
- If `notch_hz` is not null: essentially **no** energy at that frequency
  (a spur there above 5% of the largest tone amplitude fails). Never
  synthesize anything at the notch frequency.

## Constraints

- Do not modify `/app/specs/main_spec.json`.
- The verifier runs your program unchanged on hidden specs; do not
  hard-code the shipped spec's values or path.
- No network access at verify time. `numpy` is installed; the
  standard-library `wave` and `random` modules are enough for the writer.
