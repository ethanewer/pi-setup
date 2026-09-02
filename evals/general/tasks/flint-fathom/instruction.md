# Flint Fathom — sports video end-to-end pipeline

You are handed a single container and must produce a **working** video-analysis
pipeline end to end: a short running clip is fetched from a public mirror,
trimmed to its trailing seconds, its **takeoff** and **landing** frames are
detected, and an ordered list of operator commands is extracted from a session
transcript into a plain-text file.

Work only inside the container. `/tests` and `/solution` are **not** available to
you (do not attempt to read them). `python3`, `pip`, `opencv-python-headless`,
`numpy`, `ffmpeg`, `ffprobe` and `curl` are preinstalled. There is **no network
access** other than localhost. All of your output artifacts live under `/app`.

---

## Fixed fixtures (do not modify these bytes)

| `/app/fixtures/media_source.mp4` | A read-only **mirror** of the public source clip: 30 fps, 320×240, 180 frames (`0..179`), a fixed flat-track scene with a single bright running subject. |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| `/app/fixtures/transcript.txt`    | A typed-command session transcript (see §4).                                        |

The video scene is synthetic but realistic: a stationary camera, a flat **track**
band along the bottom, and one bright **subject** that stands on or leaves/returns
to the ground over the clip; nothing else moves.

---

## Deliverables (all required)

| Path | What it must be |
|------|-----------------|
| `/app/fetch_media.sh` | Executable script that fetches the media mirror over HTTP and saves it as a viewable mp4 at `/app/source.mp4`. |
| `/app/source.mp4` | The fetched source clip — a playable mp4 (180 frames @ 30 fps). |
| `/app/clip.mp4` | The **trailing** segment of `source.mp4`, trimmed out into its own playable mp4 (60 frames @ 30 fps). |
| `/app/detect_frames.py` | Pure-CPU frame-analysis program that reports takeoff/landing frame indices for any such clip. |
| `/app/events.json` | The detection result for `/app/clip.mp4`. |
| `/app/extract_commands.py` | Transcript extractor (see §4). |
| `/app/commands.txt` | The ordered operator commands, one per line. |

---

## §1 — Fetch → `/app/source.mp4`

`/app/fetch_media.sh` must:

- Accept optional args `[URL] [OUT]` with defaults = the mirror URL and
  `/app/source.mp4` respectively.
- Perform a **real HTTP download** of the payload and write the **binary** bytes
  to `OUT`. The intended offline pattern: start a short-lived local server
  (`python3 -m http.server` rooted at `/app/fixtures`, e.g. on port `8765`),
  `curl` down `http://127.0.0.1:<port>/media_source.mp4`, and tear the server down
  when done (e.g. with a `trap`).
- Be executable (`chmod +x /app/fetch_media.sh`).

After it runs, `/app/source.mp4` must be a **readable mp4** (180 frames @ 30 fps).

---

## §2 — Trim → `/app/clip.mp4`

Create `/app/clip.mp4` by keeping **only the trailing tail** of `/app/source.mp4`:
drop the leading portion and keep **exactly the last 60 frames** (source frames
`120..179`) as a new playable mp4, ~30 fps, video-only (no audio). Use `ffmpeg`
(e.g. a re-encode filtered with `select='gte(n,120)'` plus `setpts=PTS-STARTPTS`
and `-r 30`). Leave `/app/source.mp4` untouched.

---

## §3 — Frame analysis → `/app/events.json`

Write an executable `python3` program `/app/detect_frames.py` that works on
`/app/clip.mp4` **and on any such clip** (same kind of scene: fixed track band,
one bright moving subject).

### Interface

    python3 /app/detect_frames.py <video.mp4> <out.json>

It decodes the video with OpenCV, locates the subject in every frame, tracks its
vertical position, computes the two event frames, **writes** the JSON object to
`<out.json>` and **also prints** the same JSON (one line) to stdout.

### Output schema

```json
{ "takeoff_frame": <int-or-null>, "landing_frame": <int-or-null> }
```

### Semantics (frame indices are 0-based within the input clip)

- **Resting baseline:** the subject's bottom row while standing on the ground.  Because the standing pose is the lowest position the subject ever reaches, it  equals the **largest bottom-row value** observed across the clip (tolerating a  pixel or two of packing/compression).
- **Off ground:** the subject's bottom row is strictly above the baseline by a
  clear margin. A frame with no detected subject counts as *not off ground*.
- **takeoff_frame** = index of the **first** frame in which the subject is off
  ground.
- **landing_frame** = index of the **first** frame, *strictly after* some
  off-ground frame, in which the subject is **back** at the baseline (no longer
  off ground).

Edge cases the graders probe on hidden clips:

1. If the subject is **never** off ground anywhere → `takeoff_frame` and
   `landing_frame` are both `null`.
2. If the subject leaves the ground but the clip **ends before it returns** →
   `takeoff_frame` = that first off-ground index, `landing_frame` = `null`.
3. An ordinary, fully-observed jump → integer for both fields.

Do **not** hard-code numbers: compute the events from the actual frames. Produce
`events.json` by running the program on `/app/clip.mp4`:

    python3 /app/detect_frames.py /app/clip.mp4 /app/events.json

---

## §4 — Transcript → `/app/commands.txt`

`/app/fixtures/transcript.txt` is a log of a measurement console session. Each
line is either a **user-typed command** of the form

    HH:MM:SS USER> <command text>

or a non-command line (`HH:MM:SS BOOT ...`, `HH:MM:SS SYS ...`, comments starting
with `#`, blank lines).

Write `/app/extract_commands.py` (executable) that runs:

    python3 /app/extract_commands.py <transcript.txt> [out.txt]

Rules — the extractor must:

1. For each line matching the `USER>` form, take everything **after `USER>`**,
   trimmed of leading/trailing whitespace.
2. Ignore all other lines and any empty command text.
3. Preserve **first-seen order** (no dedup, no reordering).
4. Print the resulting commands to stdout, **exactly one per line, no blank
   lines, and no trailing newline other than the final line-break**.
5. If `out.txt` is given, write the identical content to that file as well.

Create `/app/commands.txt` by running the extractor on
`/app/fixtures/transcript.txt`.

The verifier checks that `commands.txt` is the exact ordered command list, with
each command on its own line and no empty lines.

---

## What is graded

The grader re-executes your programs against hidden and delivery inputs and
byte-alignments the emitted files:

- `/app/source.mp4` is a readable mp4; `/app/fetch_media.sh` is executable and a
  real HTTP worker.
- `/app/clip.mp4` is the 60-frame trailing tail of the source (runnable,
  decodable).
- Re-running `/app/events.json` `/app/detect_frames.py /app/clip.mp4` reproduces
  `/app/events.json`, and re-running it on **hidden annotated clips** yields the
  configured `null`/index semantics.
- Re-running `/app/extract_commands.py` on the fixture transcript reproduces
  `/app/commands.txt`, and running it on a **hidden transcript** yields the
  expected ordered one-per-line list.

Any missing artifact, wrong container/format, drifted index, or formatting
mistake gives 0.