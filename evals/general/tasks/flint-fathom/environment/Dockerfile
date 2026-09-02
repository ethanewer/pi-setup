FROM bench-base:ubuntu-24.04

WORKDIR /app

# Video/toolchain stack used by the pipeline and the verifier.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg curl python3 python3-pip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --break-system-packages --no-cache-dir opencv-python-headless numpy

# Fixtures and provided tools (the "flint-fathom" projects repo).
COPY files/ /app/

# Build the read-only mirror of the source clip (static fixture). The scene
# parameters live only at build time; the generator is removed from /app so no
# ground truths are discoverable inside the live container.
RUN python3 /app/gen_video.py \
        --out /app/fixtures/media_source.mp4 \
        --total 180 --fps 30 --takeoff 150 --land 170 --peak 24

RUN rm -f /app/gen_video.py

# The agent must never find tests/ or solution/ inside the image.