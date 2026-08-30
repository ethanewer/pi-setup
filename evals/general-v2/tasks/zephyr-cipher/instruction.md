# zephyr-cipher — DSP studio signal-processing utility

A digital signal-processing studio needs five small utilities written as a
single reusable program. You must write **one executable Python program** at
`/app/solve.py` that, given a scenario directory, recovers every requested datum
and writes the deliverables described below.

## Deliverable

Write an executable program at `/app/solve.py`:

```
python3 /app/solve.py <input_dir> <output_dir>
```

- `<input_dir>` is a scenario directory (see *Input layout*). Your program must
  accept it on the command line; it may **not** assume a fixed path and may not
  hard-code the shipped scenario's location.
- `<output_dir>` is where you write your outputs. Create it if needed.
- The program must work on **any** scenario directory with the same layout,
  including unseen ones (the grader re-runs it on fresh scenarios).
- On every run it must write `<output_dir>/answer.json` plus a 16-bit wav file
  and a magnitude CSV (details below). When invoked with `/app` as
  `<output_dir>` (as the grader does), this creates the deliverable file
  `/app/answer.json`.

Python packages available (require nothing else): `numpy`, `scipy`,
`soundfile`, `vosk`, and the standard-library `wave`. The system tool
`ffmpeg` is installed and on `PATH`. A vosk acoustic model is preinstalled at
`/opt/vosk/vosk-model-small-en-us-0.15` — use exactly that path.

## Input layout

Each scenario directory contains these files:

| file              | meaning                                                            |
|-------------------|--------------------------------------------------------------------|
| `stft_signal.npy` | a 1-D `float64` numpy array (samples of a test signal)             |
| `stft_params.json`| JSON of the exact STFT parameters to use (see below)               |
| `spectrum.txt`    | a nonstandard delimited spectrum file (see *Spectrum parsing*)     |
| `tone.json`       | JSON of multitone synthesis parameters (see *Multitone wav*)       |
| `speech.mp3`      | a short speech recording to transcribe (see *Transcription*)       |

## answer.json

Write `<output_dir>/answer.json` containing exactly these keys:

```
{
  "stft_mag":            [[...per-frame...], ...],   # linear magnitudes
  "stft_mag_csv":        "stft_mag.csv",            # exported CSV filename
  "stft_freqs":          [ ... ],                   # frequency axis (Hz)
  "stft_frames_s":       [ ... ],                   # frame-center times (s)
  "spec_x":              [ ... ],                   # parsed wavelength (nm)
  "spec_y":              [ ... ],                   # parsed intensity
  "wavenumber_peaks_cm1":[ ... ],                   # sorted peak wavenumbers
  "tone_wav":            "tone.wav",                # produced wav filename
  "transcript":          "the spoken words..."
}
```

### 1) Short-time Fourier transform (STFT) magnitudes

Read `stft_params.json`; it holds `fs`, `window`, `nperseg`, `noverlap`,
`nfft`, `one_sided`, and `boundary`. Compute the STFT of `stft_signal.npy`
with **exactly these parameters** using `scipy.signal.stft`, mapping
`one_sided` to scipy's `return_onesided` argument and passing `boundary`
through unchanged (it may be `null`).

Take the **linear magnitude** (`np.abs`) of the complex STFT — do **not**
convert to dB. Store `stft_mag` as the transpose of the magnitude matrix so
each **row is one frame** and each **column is one frequency bin**
(shape `nframes × nfreq`). Also write the same values to
`<output_dir>/stft_mag.csv` as comma-separated text, one frame per line.

The grader re-computes the STFT independently with `scipy.signal.stft` using
the same parameters and compares the magnitudes, so using the documented
parameters and linear magnitude is essential.

### 2) Parse a nonstandard delimited spectrum file

`spectrum.txt` holds a two-column spectrum whose numbers use a **localized
decimal separator**: the decimal point is written as a comma (`,`), the two
columns are separated by a semicolon (`;`), and there is an optional header
line and free whitespace. Example line:

```
501,23; 0,44721
```

Parse it into clean numeric arrays: column 1 is wavelength in **nanometres
(nm)**, column 2 is intensity. Store them as `spec_x` and `spec_y`. Skip/handle
the header and blank lines. The grader re-parses the file independently and
checks your arrays match.

### 3) Convert wavelength to wavenumber and report peaks

Convert each wavelength sample from nm to wavenumber in **cm⁻¹**:

```
wavenumber_cm1 = 1e7 / wavelength_nm
```

The spectrum contains a small number of well-separated Gaussian peaks. Identify
each **local maximum** of intensity (a sample whose intensity is strictly
greater than its immediate neighbours; because the peaks are well separated
this is unambiguous). For every local maximum, report `1e7 / wavelength_nm` at
that sample. Store the **sorted** list in `wavenumber_peaks_cm1`. The grader
compares these to its own calculation with a small tolerance, so the exact
reciprocal conversion matters.

### 4) Multitone synthesis, normalization, and 16-bit wav

Read `tone.json`; it holds `frequencies` (Hz), `amplitudes` (relative),
`duration_s`, `sample_rate`, `target_rms`, `dither` (bool), and `seed`.

Generate a mono signal of length `int(round(duration_s * sample_rate))`
samples at the given `sample_rate`:

```
t    = arange(n) / sample_rate
s    = sum(amp_i * sin(2*pi*freq_i * t))   for each i
```

If `dither` is true, add a tiny uniform dither (e.g. one LSB) drawn with a
seeded RNG (use `seed`). Then **RMS-normalize**: scale `s` so its RMS equals
`target_rms`. Finally quantize to 16-bit PCM (clip to the int16 range) and
write a mono, 16-bit, `sample_rate`-Hz WAV file at `<output_dir>/tone.wav`
using the standard-library `wave` module. Do not use a header bigger than the
standard 44-byte WAV header. Set `answer["tone_wav"]` to `"tone.wav"`.

The grader checks the WAV header (mono, 16-bit, correct sample rate and
duration), that the decoded RMS is within ±0.02 of `target_rms`, and that a
spectral peak appears at every frequency listed in `tone.json`. Keep the RMS
normalization exact and make sure every requested tone is present.

### 5) Speech-only transcription (mp3 → text)

`speech.mp3` is a short, clear spoken phrase. Transcribe it to text. Decode the
mp3 to 16 kHz mono 16-bit PCM (a simple `ffmpeg` subprocess writing raw `s16le`
to stdout is convenient) and feed it to the preinstalled vosk model at
`/opt/vosk/vosk-model-small-en-us-0.15` (Language: English, sample rate 16000).
Store the transcribed words (lower-cased, space-separated, no punctuation) in
`answer["transcript"]`. The grader compares your transcript (ignoring case and
non-alphanumeric characters) to the ground-truth phrase, so return exactly the
recognized words — do not invent or paraphrase them.

## Constraints

- Do not modify `/app/solve.py`'s interface. It must accept two CLI arguments.
- Do not hard-code the shipped scenario path; always take `<input_dir>`.
- Do not require any package beyond those listed above, and do not download
  anything at runtime (the model is already installed).
- `answer.json` must contain exactly the documented keys and be valid JSON.
