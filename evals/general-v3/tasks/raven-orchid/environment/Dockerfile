FROM bench-base:python-3.12

WORKDIR /app

ENV VOSK_MODEL=/app/vosk-model

# Media ingest needs ffmpeg for audio extraction + transcoding.
# psmisc provides `fuser`, which the verifier uses to free its media-server
# port from any lingering listener (e.g. a server the agent left running).
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg psmisc && rm -rf /var/lib/apt/lists/*

# Scientific-array + transcription stack.
RUN pip install --no-cache-dir numpy scipy tifffile vosk

# Fixtures (media files, TIFF frames, spectra, animation spec, media server,
# URL list, and the small offline ASR model) all ship inside the image.
COPY files/ /app/
