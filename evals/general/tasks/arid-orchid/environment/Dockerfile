FROM bench-base:ubuntu-24.04

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

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
    && python3 -m pip install --no-cache-dir --break-system-packages numpy==2.5.3 pillow==12.3.0

COPY files/ /app/

RUN chmod -R ugo+rX /app && \
    touch /app/.write_test && rm -f /app/.write_test