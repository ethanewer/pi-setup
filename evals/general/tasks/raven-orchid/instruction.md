# Gryphon Relay media-ingest pipeline

Build four reusable command-line programs that implement a media-ingest and
scientific-array workflow, then run each one against the provided fixtures to
produce the required output files **in `/app`**.

The grading harness re-runs **your** four programs, unchanged, against a hidden
set of the same kinds of inputs (different media URLs, TIFF sets, magnitude
arrays, and animation specs). So each program must work on *any* conforming
input — never hard-code to the shipped filenames, values, or lengths.

## Environment

- Working directory: `/app`. Python 3.12 is `python3`. `ffmpeg` is installed.
  The Python packages `numpy`, `scipy`, `tifffile`, and `vosk` are installed.
- A small offline speech-recognition model ships at `/app/vosk-model`.
- `ffmpeg` is already installed (used by `ingest.py` to extract audio tracks).
- **Do not modify** these supplied fixture files (they are inputs, not products):
  - `/app/sources.txt`, `/app/serve_media.py`
  - everything under `/app/media_src/`
  - `/app/tif_visible/`
  - `/app/spectra_visible/magnitudes.npy` and `/app/spectra_visible/settings.txt`
  - `/app/anim_visible/anim-spec.json`

## Deliverables (all required)

Programs (write them yourself):

1. `/app/ingest.py`
2. `/app/stack.py`
3. `/app/peaks.py`
4. `/app/animation.py`

Outputs your programs produce **when run against the shipped fixtures**:

5. `/app/media/manifest.json` (via `ingest.py`)
6. `/app/transcript-raw.txt` (via `ingest.py`)
7. `/app/transcript.txt` (via `ingest.py`)
8. `/app/stack-shape.txt` (via `stack.py`)
9. `/app/peaks.csv` (via `peaks.py`)
10. `/app/animation.json` (via `animation.py`)

---

## 1. `ingest.py` — the media downloader and transcriber

```
python3 /app/ingest.py <urls_file> <media_out_dir> <raw_transcript> <clean_transcript>
```

Reads `<urls_file>` line by line. An empty or whitespace-only line is **ignored**.
For every other line, the program treats it as a URL to fetch over HTTP from a
local media server (the provided `/app/serve_media.py` server).

Deterministic naming (this is the point of the stage):
- Every downloaded file is stored under
  `<media_out_dir>/sha256(<exact URL string as it appears on the line>).<ext>`,
  where `ext` is the lowercase extension of the last path segment of the URL —
  a `?query` on the URL line, if any, is part of the exact string that is
  hashed and never part of the filename extension.
- A manifest is written to `<media_out_dir>/manifest.json`:

```json
{
  "entries": [
    {
      "url": "<full url as given>",
      "kind": "video" | "image" | "audio" | "other",
      "status": 200,
      "file": "<sha256(url)+ext, or \"\" on failed fetch>",
      "url_sha256": "<hex sha256 of the exact url string>",
      "bytes_sha256": "<hex sha256 of downloaded body, or ''>"
    },
    ...
  ]
}
```

Entries appear in the same order as the URLs in the input file. `status` is the
HTTP status code (e.g. `200`, `404`) on a served answer, or the string `"ERR"`
if the connection itself failed. A URL answered with a status other than `200`
is **not** saved (`file` and `bytes_sha256` are empty).

`kind` is derived from the lowercase extension of the request path:
- video: `.mp4 .mov .m4v .webm .avi .mkv`
- image: `.jpg .jpeg .png .gif .webp .bmp`
- audio: `.mp3 .wav .m4a .aac .ogg .flac`
- anything else: `other` (still downloaded and saved under its own extension).

Transcription: for every **video** entry with status `200`, extract the audio
track with `ffmpeg` (decode to a mono 16 kHz 16-bit PCM WAV) and transcribe it
with the offline vosk model (`/app/vosk-model`). Each video contributes exactly
**one line** to `<raw_transcript>`, in URL order (videos only; images/audio do
not add lines). If a video produces no recognized text, its line is empty.

- `<raw_transcript>` holds one line per transcribed video (the raw ASR text),
  with a trailing newline if the file is non-empty.
- `<clean_transcript>` holds the **normalized** copy of the raw transcript:
  per line, lowercase everything, drop every character that is not `a–z`, `0–9`,
  or a space, collapse runs of spaces into one space, and strip leading/trailing
  whitespace. Line boundaries from the raw file are preserved.

### ingest edge cases the hidden cases probe
- Blank/whitespace-only lines are skipped entirely (they produce no entry).
- A URL that answers `4xx`/`5xx` produces an entry with that status, an empty
  `file`, and no saved body, and is not transcribed.
- Audio and image URLs are downloaded and hashed but never transcribed.
- A scenario with **no video** yields empty (but still created)
  `raw_transcript` and `clean_transcript` files.
- The exact URL string (including any `?query`) is what is hashed.

### Produce the visible deliverable outputs
Start the bundled media server serving the shipped media, then run:

```
python3 /app/serve_media.py /app/media_src 8787 &
sleep 1
python3 /app/ingest.py /app/sources.txt /app/media /app/transcript-raw.txt /app/transcript.txt
```

This creates `/app/media/manifest.json`, `/app/transcript-raw.txt`, and
`/app/transcript.txt`.

---

## 2. `stack.py` — concatenate a stack of images along a new axis

```
python3 /app/stack.py <tif_dir> <shape_out> [stack_out.npy]
```

- Read every `.tif`/`.tiff` file in `<tif_dir>` (compared case-insensitively,
  sorted by name; non-TIFF files are ignored).
- A TIFF that holds multiple pages/channels loads as a 3D array; only its first
  (index 0) page is used as that file's single 2D frame.
- **Single frame** → a 2D array of shape `(H, W)`.
- **Several frames** → a 3D array of shape `(N, H, W)` stacked along a new
  leading (depth) axis.
- Write to `<shape_out>` exactly one of:
  - `H,W` (single frame, e.g. `5,4`)
  - `N,H,W` (several frames, e.g. `3,5,4`)
  - `EMPTY` if no TIFF files are present
  - `INCOMPATIBLE` if the frames do not all share one shape
- If `<stack_out.npy>` is given, save the resulting numpy array there too.

Produce the visible deliverable:

```
python3 /app/stack.py /app/tif_visible /app/stack-shape.txt /app/stack.npy
```

---

## 3. `peaks.py` — per-frame top-k frequency-bin peaks

```
python3 /app/peaks.py <magnitudes.npy> <k> <out.csv>
```

- `<magnitudes.npy>` is a numpy numeric array; rows are frames and columns are
  frequency bins (a 1D array is treated as a single frame). The verifier checks
  exact bin ordering.
- For each frame, rank the bins by **magnitude value descending** and write the
  top-`k` bins in that order. `k` is the integer value passed on the command
  line.
- Ties keep the lower-numbered bin first (a row of all-equal finite values is
  a tie, so with a large `k` every bin still appears, in natural order).
- `k < 0` is treated as `0` (no bins). `k` above the number of bins returns
  **all** bins. A frame is *degenerate* when it contains any non-finite value
  (`NaN` or `±inf`); a degenerate frame yields no bins (bare frame index).
- The output CSV has header `frame,bins` and one row per frame: the frame index
  (0-based) followed by the chosen bins in descending magnitude order,
  comma-separated. A frame with no bins emits a bare frame index (no trailing
  comma). Example:

```
frame,bins
0,5,2,11
1,0,7
2,4
```

- If `<magnitudes.npy>` cannot be read as a 1D/2D numeric array, write exactly
  one line `ERROR`.

Produce the visible deliverable (K is read from the settings file):

```
python3 /app/peaks.py /app/spectra_visible/magnitudes.npy "$(sed -n 's/^k=//p' /app/spectra_visible/settings.txt)" /app/peaks.csv
```

---

## 4. `animation.py` — emit animation records with timelines and keyframes

```
python3 /app/animation.py <spec.json> <out.json>
```

Input `<spec.json>`:

```json
{
  "timelines": [
    {"name": "pan",  "keyframe_count": 5},
    {"name": "spin", "keyframe_count": 9}
  ]
}
```

Output `<out.json>` has one record per timeline:

```json
{
  "source": "gryphon-anim",
  "timelines": [
    {
      "name": "pan",
      "declared_count": 5,
      "keyframes": {
        "time":         [ 0.0, 0.2, 0.4, 0.6, 0.8 ],
        "translation":  [ [x, y, z], ... ],
        "rotation":     [ 0.0, ..., ... ],
        "scale":        [ [sx, sy, sz], ... ]
      }
    }
  ]
}
```

Constraints the verifier enforces:
- `declared_count` equals the spec's `keyframe_count` for that timeline.
- `time`, `translation`, `rotation`, and `scale` all have **exactly**
  `declared_count` elements.
- `time` is strictly increasing.
- Every `translation` and `scale` row has exactly 3 numeric components;
  `rotation` is numeric.
- A `keyframe_count` that is missing, negative, fractional (e.g. `2.5`), or
  non-numeric is emitted as `0`, i.e. all four arrays are empty for that
  timeline.
- A spec that is not valid JSON or lacks a `timelines` list produces
  `{"error": "INVALID_SPEC", "timelines": []}`.
- An empty `timelines` list produces `{"timelines": []}`.
- More than one timeline, duplicate names, and large counts are all fine.

Produce the visible deliverable:

```
python3 /app/animation.py /app/anim_visible/anim-spec.json /app/animation.json
```

---

## Constraints

- The verifier runs `/app/ingest.py`, `/app/stack.py`, `/app/peaks.py`, and
  `/app/animation.py` on **fresh inputs** (including edge/malformed ones) with the
  exact command-line shapes above, so keep the interfaces exactly as documented
  and the behavior correct on *any* conformal input.
- Do not hard-code to the fixture files' names, shapes, counts, or magnitudes.
- No network access at verify time beyond your own local media server; use only
  the shipped `/app/vosk-model` for ASR.
- Do not modify the listed supplied fixtures.
- All four programs must be runnable via `python3 /app/<name>.py ...`.