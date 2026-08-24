FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

# Generate 50 solid-color frames (16x16, 10 fps, 5 s) in 5 color bands.
RUN python3 - <<'PY'
cols = [(255,0,0)]*10 + [(0,255,0)]*10 + [(0,0,255)]*10 + [(255,255,255)]*10 + [(0,0,0)]*10
with open('/app/frames.raw','wb') as f:
    for c in cols:
        f.write(bytes(list(c)) * (16*16))
PY

# Mux the raw frames into an mp4 (all-intra for exact seeking).
RUN ffmpeg -y -f rawvideo -pix_fmt rgb24 -s 16x16 -r 10 -i /app/frames.raw -c:v libx264 -pix_fmt yuv420p -g 1 /app/video.mp4

RUN rm /app/frames.raw