FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

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
