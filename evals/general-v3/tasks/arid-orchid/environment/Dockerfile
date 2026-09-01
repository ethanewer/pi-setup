FROM bench-base:ubuntu-24.04

WORKDIR /app

# Software-only rendering stack: GCC + Python + an OSMesa (headless GL) dev lib.
# No X server, no GPU, no systemd.
RUN apt-get update -y && apt-get install -y --no-install-recommends \
        gcc \
        build-essential \
        python3 \
        python3-pip \
        python3-numpy \
        python3-pil \
        fonts-dejavu-core \
        libgl1-mesa-dev \
        libosmesa6-dev \
        mesa-utils \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m pip install --no-cache-dir --break-system-packages numpy pillow

COPY files/ /app/

RUN chmod -R ugo+rX /app && \
    touch /app/.write_test && rm -f /app/.write_test