#!/usr/bin/env bash
# Oracle for zephyr-orchid: real media pipeline — download, trim, transcribe.
# Works only against /app fixtures; never reads /tests.
set -euo pipefail

cd /app

TRIM_SECS=3.0
PRIMARY_PORT=8734
SRC="/app/media/source.mp4"
AUDIO="/app/media/audio.wav"
MODEL="/opt/vosk-model"

echo "== [1/4] fetch_media.sh =="
cat > /app/fetch_media.sh <<'SH'
#!/usr/bin/env bash
# fetch_media.sh <URL> <output.mp4>
# Download a web video stream and save it as a viewable MP4 file.
# Prints "ok <duration_seconds>" on success, non-zero exit on failure.
set -euo pipefail
url="${1:?usage: fetch_media.sh <url> <out.mp4>}"
out="${2:?usage: fetch_media.sh <url> <out.mp4>}"
tmp="$(mktemp --suffix=.mp4)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 2 "$url" -o "$tmp"
# Re-mux to a clean baseline MP4 container so the result is always viewable.
ffmpeg -y -loglevel error -i "$tmp" -c copy -movflags +faststart -y "$out"
dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")"
echo "ok duration=$dur"
SH
chmod +x /app/fetch_media.sh

# Serve the fixture mirror and download the source clip the intended way.
( cd /app/media && exec python3 -m http.server "$PRIMARY_PORT" >/dev/null 2>&1 ) &
SRV=$!
sleep 1
trap 'kill $SRV 2>/dev/null' EXIT
/app/fetch_media.sh "http://127.0.0.1:${PRIMARY_PORT}/source.mp4" "/app/source_stream.mp4"

echo "==> [2/3] trim trailing segment -> clip.mp4 =="
D="$(ffprobe -v error -show_entries format=duration -of csv=p=0 /app/source_stream.mp4)"
start="$(python3 -c "print(max(0.0,(${D} - ${TRIM_SECS})))")"
# Frame-accurate re-encode of the final <TRIM_SECS> seconds.
ffmpeg -y -loglevel error -ss "$start" -i /app/source_stream.mp4 -t "$TRIM_SECS" \
    -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -movflags +faststart \
    /app/clip.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 /app/clip.mp4

echo "==> [3/3] DNS backend -> transcript.txt =="
cat > /app/transcribe.py <<'PY'
#!/usr/bin/env python3
"""transcribe.py <input.wav> [output.txt]

CPU-only speech recognition (vosk + provided small model). Reads any mono/stereo
WAV at any sample rate, transcribes it, normalises the text, and writes the
normalised transcript to [output.txt] (or stdout if omitted).
"""
import json
import sys
import wave

def normalise(text: str) -> str:
    out = []
    for ch in text.lower():
        out.append(ch if (ch.isalnum() or ch == " ") else " ")
    return "".join(s for s in " ".join("".join(out).split()) )

def transcribe(wav_path: str) -> str:
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)
    model = Model("/opt/vosk-model")
    with wave.open(wav_path, "rb") as wf:
        rate = wf.getframerate()
        rec = KaldiRecognizer(model, rate)
        while True:
            data = wf.readframes(4000)
            if not data:
                break
            rec.AcceptWaveform(data)
        result = json.loads(rec.FinalResult())
    return result.get("text", "")

def main(argv):
    if len(argv) < 2:
        sys.exit("usage: transcribe.py <input.wav> [output.txt]")
    text = normalise(transcribe(argv[1]))
    if len(argv) >= 3 and argv[2] != "-":
        with open(argv[2], "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    else:
        sys.stdout.write(text + "\n")

if __name__ == "__main__":
    main(sys.argv)
PY
chmod +x /app/transcribe.py
/app/transcribe.py /app/media/audio.wav /app/transcript.txt
cat /app/transcript.txt

echo "DONE"