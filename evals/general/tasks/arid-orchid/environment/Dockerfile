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

# numpy and pillow are pinned to the versions the apt packages above provide
# (python3-numpy 1.26.4, python3-pil 10.2.0), not to the newest on PyPI. These two
# requirements used to be bare, which pip read as "already satisfied" and left
# alone; pinning them to today's PyPI versions instead made pip try to upgrade over
# a Debian-installed package, which fails with "Cannot uninstall numpy 1.26.4,
# RECORD file not found. Hint: The package was installed by debian." -- Debian
# packages carry no RECORD, so they cannot be uninstalled by pip at all.
# --ignore-installed keeps pip from touching the Debian copy while still fixing the
# version, so the environment stays the one this task was validated against even if
# the Ubuntu archive moves.
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
    && python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
        numpy==1.26.4 pillow==10.2.0

COPY files/ /app/

RUN chmod -R ugo+rX /app && \
    touch /app/.write_test && rm -f /app/.write_test