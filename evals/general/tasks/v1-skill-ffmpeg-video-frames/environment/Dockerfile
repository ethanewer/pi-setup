FROM bench-base:ubuntu-24.04
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
RUN ffmpeg -y -f lavfi -i testsrc=duration=2:size=160x120:rate=10 -c:v libx264 -pix_fmt yuv420p -r 10 /app/sample.mp4 2>/dev/null