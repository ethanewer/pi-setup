# Media pipeline: web-video download, trailing-clip trim, CPU speech transcription

You are building a small media-processing pipeline. Everything runs on CPU — no GPU.
Your working directory is `/app`. Produce **four deliverables** there:

1. `/app/fetch_media.sh` — a generic script that downloads a web video into a viewable `.mp4`.
2. `/app/clip.mp4` — a trimmed clip containing only the **final 3 seconds** of the source clip.
3. `/app/transcribe.py` — a CPU-only speech-to-text driver.
4. `/app/transcript.txt` — the normalized transcription of the provided audio.

Read carefully — the verifier executes each deliverable on cases you have not seen.

---

## 1. `/app/fetch_media.sh` (web-video download)

Create an executable POSIX script with this usage contract:

```
fetch_media.sh <source-url> <output.mp4>
```

- It must fetch the media at `<source-url>` over HTTP(S) (use `curl`) and save a
  **viewable MP4** at `<output.mp4>`.
- "Viewable" means the file is a well-formed MP4 container carrying a real video
  stream (a codec like `h264`, `h265/hevc`, `av1`, `mpeg4`, etc.). Re-muxing to
  a baseline MP4 container (`ffmpeg -c copy -movflags +faststart` after download)
  is recommended so odd web streams play reliably.
- It must **fail (non-zero exit)** if the download or the mux fails.
- It must work on **any** URL, including URLs with a query string
  (e.g. `http://host/path/clip.mp4?token=xyz`) and on clips of different
  resolutions and durations.
- Make the script executable: `chmod +x /app/fetch_media.sh`.

### Fetch the primary source clip
A copy of the public source video is staged on disk at `/app/media/source.mp4`.
It is **exposed over HTTP** as `http://127.0.0.1:8734/source.mp4` so this really
tests a network fetch. Before downloading, start the local mirror:

```bash
( cd /app/media && exec python3 -m http.server 8734 >/dev/null 2>&1 ) &
sleep 1
```

Then fetch it through your script into `/app/source_stream.mp4`:

```bash
/app/fetch_media.sh http://127.0.0.1:8734/source.mp4 /app/source_stream.mp4
```

The source clip is **9.0 seconds** long. Verify by inspecting
`/app/source_stream.mp4` with `ffprobe` (or `mkvpropedit`/`mediainfo` if you
prefer). Good tools present: `curl`, `ffmpeg`, `ffprobe`, `python3`.

Do not hard-code the server port or the source path into `fetch_media.sh` — it
must remain generic.

---

## 2. `/app/clip.mp4` (trailing-segment trim)

From `/app/source_stream.mp4`, cut a new clip `/app/clip.mp4` that keeps **only
the final 3 seconds** and drops the rest (i.e., seconds `[6.0, 9.0]`, or
`[D-3, D]` where `D` is the actual duration you measure — do **not** hard-code;
measure it with `ffprobe`).

Requirements:
- `/app/clip.mp4` must be a valid MP4 with a video stream whose duration is
  ~3.0 seconds (a re-encode is fine, e.g. `libx264 -pix_fmt yuv420p`).
- The content must be an accurate copy of the source's last three seconds; the
  verifier compares your clip against the source trailer (PSNR must be high).

Example skeleton (measure `D`, then cut the tail):

```bash
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 /app/source_stream.mp4)
START=$(python3 -c "print(max(0.0, float('$D') - 3.0))")
ffmpeg -y -ss "$START" -i /app/source_stream.mp4 -t 3 -an \
    -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p /app/clip.mp4
```

---

## 3. `/app/transcribe.py` (CPU speech recognition)

A CPU-only automatic speech recognition (ASR) backend is **already provisioned**:

- Python package `vosk` is installed (`python3 -c "import vosk"`).
- The speech model (small-English, ~40 MB) is unpacked at **`/opt/vosk-model`**
  (files include `graph`, `am`, `conf`, `ivector`, `README`).

Author an executable `/app/transcribe.py` with this usage contract:

```
transcribe.py <input.wav> <output.txt>
```

- It runs a real speech-recognition pass **on CPU** using vosk + `/opt/vosk-model`.
- It must handle **wav files of any sample rate or channel count** (vosk accepts
  the file's frame rate — resample coverage where needed is allowed, e.g. feed
  `KaldiRecognizer` the `wf.getframerate()`).
- It writes one normalized transcript line to `<output.txt>`.
- When called with only `<input.wav>` (no output argument) it prints the same
  line to stdout and exits 0.

### Normalization contract (exact)
The transcript text you write must be **normalized** with this exact algorithm:

1. lowercase the entire string;
2. replace every character that is **not** an ASCII letter, ASCII digit, or a
   space by a **single space**;
3. collapse any run of whitespace into one space;
4. strip leading/trailing spaces.

A transcript with no recognised speech must normalize to the empty string
(that is fine too).

### Produce the transcript deliverable
Audio you must transcribe is **`/app/media/audio.wav`**. Run your script on it:

```bash
python3 /app/transcribe.py /app/media/audio.wav /app/transcript.txt
```

`/app/transcript.txt` must be exactly the normalized transcription (one line,
single trailing newline acceptable). The verifier will call `transcribe.py`
against the same audio (and yes, unknown hidden WAVs at odd sample rates) and
compare normalized outputs — so implement the *real* recognition, not a canned
answer.

---

## What the verifier does (so you can be sure)

- Replays `/app/fetch_media.sh` on hidden media URLs (different durations,
  resolutions, query strings) and checks the result is a valid MP4 of the
  expected length with a video codec.
- Checks `/app/clip.mp4`: valid MP4, duration ~3 s, and content matches the
  source trailer (PSNR threshold).
- Runs `/app/transcribe.py` on `/app/media/audio.wav` and on hidden WAV files
  (including a 44.1 kHz one), and checks the normalized transcript of each.
- Validates `/app/transcript.txt`.

## Constraints

- Use only the tools in the image: `curl`, `ffmpeg`/`ffprobe`, `python3` with
  `vosk`. `pip install` is allowed if needed (network available), but everything
  you need is already installed.
- Create your deliverables in `/app` as specified above. You may create
  temporary/helper files in `/app` or `/tmp`.
- Do not touch `/tests` or `/solution`.
- You may not modify `/opt/vosk-model`, `/app/media`, or the base image.
- Make `fetch_media.sh` and `transcribe.py` executable.