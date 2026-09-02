FROM bench-base:ubuntu-24.04

# ---- media pipeline toolchain -------------------------------------------------
# ffmpeg for download/transcode/trim, curl for HTTP fetch, python3 for the ASR
# driver and the tiny local media web server. vosk is the CPU-only speech
# recognition engine (small model, ~40 MB, runs entirely on CPU).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ffmpeg \
        curl \
        ca-certificates \
        python3 \
        python3-pip \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --break-system-packages --no-cache-dir vosk==0.3.45

WORKDIR /app

# Fixtures: the "public" source clip + provided audio, plus the packaged ASR model.
# The agent must unpack the model to a working directory for transcription and
# point transcribe.py at it.
COPY files/ /app/

# Unpack the provided ASR model into a conventional location. The agent uses this
# as the runtime speech-recognition model for CPU-only transcription.
RUN mkdir -p /opt/vosk-model && \
    unzip -q /app/model/vosk_model.zip -d /opt/ && \
    mv /opt/vosk-model-small-en-us-0.15/* /opt/vosk-model/ && \
    rm -f /app/model/vosk_model.zip

# Confirm the stack is live.
RUN which ffmpeg ffprobe curl python3 && \
    python3 -c "import vosk, json; print('vosk', vosk.__name__)"