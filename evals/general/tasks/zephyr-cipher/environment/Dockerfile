FROM bench-base:python-3.12
RUN apt-get update && apt-get install -y --no-install-recommends wget ffmpeg && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir numpy scipy soundfile vosk && \
    mkdir -p /opt/vosk && cd /opt/vosk && \
    wget -q https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip && \
    python3 -c "import zipfile; zipfile.ZipFile('vosk-model-small-en-us-0.15.zip').extractall('/opt/vosk')" && \
    rm vosk-model-small-en-us-0.15.zip
WORKDIR /app
COPY files/ /app/
