#!/usr/bin/env bash
# Verifier for zephyr-orchid. Runs as root AFTER the agent finishes; /tests is
# mounted read-only (hidden cases under /tests/hidden). Exercises every
# deliverable and writes REWARD to /logs/verifier/reward.txt.
set -uo pipefail

REWARD=1
FAIL(){ echo "  [FAIL] $*"; REWARD=0; }
PASS(){ echo "  [PASS] $*"; }
VHEAD="/tests/verify.py"

echo "======================== zephyr-orchid verifier ========================"

# ---------------- A. web-video download (replay fetch_media.sh on hidden URLs)
echo "== A/1 fetch_media.sh download replay on hidden media =="
if [ ! -x /app/fetch_media.sh ]; then
    FAIL "fetch_media.sh missing or not executable"
else
    ( cd /tests/hidden/media && exec python3 -m http.server 8744 >/dev/null 2>&1 ) &
    SRV=$!; sleep 1
    for src in hsig.mp4 hbanner.mp4; do
        case "$src" in
            hsig.mp4)   exp=5.0 ;;
            hbanner.mp4) exp=7.0 ;;
        esac
        out="/tmp/dl_${src%.mp4}.mp4"
        if timeout 20 /app/fetch_media.sh "http://127.0.0.1:8744/${src}?uid=42" "$out" >/dev/null 2>&1; then
            dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" 2>/dev/null)"
            nv="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$out" 2>/dev/null | tr -d '\r')"
            primer=$(echo "$dur" | python3 -c "import sys; v=sys.stdin.read().strip(); print('yes' if v and abs(float(v)-$exp)<=0.6 else 'no')" 2>/dev/null || echo no)
            if [ "$primer" = "yes" ]; then PASS "$src download, duration=$dur (exp ~$exp)"; else FAIL "$src wrong duration got='$dur' exp ~$exp"; fi
            if [ -n "$nv" ] && [ "$primer" = "yes" ]; then
                PASS "$src video codec present ($nv)"
            else
                FAIL "$src no valid video stream"
            fi
        else
            FAIL "fetch_media.sh failed on $src"
        fi
    done
    kill "$SRV" 2>/dev/null
fi

# ---------------- B. trim trailing segment -> clip.mp4
echo "== B/2 clip.mp4 trim (duration + PSNR vs source trailer) =="
SR="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 /app/media/source.mp4 2>/dev/null)"
CW="${SR%%x*}"; CH="${SR##*x}"
[ -n "$CW" ] && [ -n "$CH" ] || CW=640
[ -n "$CH" ] || CH=360
if [ ! -f /app/clip.mp4 ]; then
    FAIL "clip.mp4 missing"
else
    cdur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 /app/clip.mp4 2>/dev/null)"
    dspo=$(echo "$cdur" | python3 -c "import sys; v=sys.stdin.read().strip(); print('yes' if 2.4<=float(v)<=3.8 else 'no')" 2>/dev/null || echo no)
    [ "$dspo" = "yes" ] && PASS "clip duration=$cdur (trailer ~3.0)" || FAIL "clip duration bad got='$cdur'"
    ffmpeg -y -loglevel error -sseof -3 -i /app/media/source.mp4 -an -c:v libx264 -pix_fmt yuv420p /tmp/ora_ref.mp4
    psnr="$(ffmpeg -hide_banner -loglevel info -i /app/clip.mp4 -i /tmp/ora_ref.mp4 \
        -filter_complex "[0:v]setpts=PTS-STARTPTS,fps=25,scale=${CW}:${CH}[a];[1:v]setpts=PTS-STARTPTS,fps=25,scale=${CW}:${CH}[b];[a][b]psnr" \
        -f null - 2>&1 | grep -oE 'average:(inf|[0-9.]+)' | tail -1 | cut -d: -f2)"
    pchk=$(echo "$psnr" | python3 -c "import sys; v=sys.stdin.read().strip(); print('yes' if v=='inf' or (v and float(v)>=30) else 'no')" 2>/dev/null || echo no)
    [ "$pchk" = "yes" ] && PASS "clip matches source trailer (psnr_avg=$psnr)" || FAIL "clip is not the source trailer (psnr_avg=$psnr)"
fi

# ---------------- C. ASR transcription
echo "== C/3 primary transcript.txt =="
PRIM="the quick brown fox jumped over the lazy dog"
if [ -f /app/transcript.txt ] && python3 "$VHEAD" /app/transcript.txt "$PRIM" >/dev/null 2>&1; then
    PASS "/app/transcript.txt matches expected"
else
    FAIL "/app/transcript.txt wrong (got '$(cat /app/transcript.txt 2>/dev/null)')"
fi

echo "== C/3b transcribe.py on visible + hidden audio =="
if [ ! -x /app/transcribe.py ]; then
    FAIL "transcribe.py missing or not executable"
else
    if timeout 180 python3 /app/transcribe.py /app/media/audio.wav /tmp/chk_sample.txt >/dev/null 2>&1 \
       && python3 "$VHEAD" /tmp/chk_sample.txt "$PRIM" >/dev/null 2>&1; then
        PASS "transcribe.py reproduces sample transcript"
    else
        FAIL "transcribe.py failed on /app/media/audio.wav (out '$(cat /tmp/chk_sample.txt 2>/dev/null)')"
    fi

    # hidden cases (independent expected transcripts)
    check_hidden() {
        local wav="$1" exp="$2" tag="$3"
        local out="/tmp/${tag}_out.txt"
        if timeout 240 python3 /app/transcribe.py "$wav" "$out" >/dev/null 2>&1; then
            if python3 "$VHEAD" "$out" "$exp" >/dev/null 2>&1; then
                PASS "hidden $tag transcript ok"
            else
                FAIL "hidden $tag mismatch: got '$(cat "$out" 2>/dev/null)'"
            fi
        else
            FAIL "transcribe.py failed on hidden $tag"
        fi
    }
    check_hidden /tests/hidden/audio/one.wav   "the recipe calls for two eggs a cup of flour and some sugar" one
    check_hidden /tests/hidden/audio/two.wav   "the green turtle slowly crossed the sandy beach" two
    check_hidden /tests/hidden/audio/three.wav "they decided to meet at the library after the meeting finished" three
    check_hidden /tests/hidden/audio/four.wav  "several kinds of birds gather in the park each morning" four
fi

echo "REWARD=$REWARD"
mkdir -p /logs/verifier
echo "$REWARD" > /logs/verifier/reward.txt
exit 0