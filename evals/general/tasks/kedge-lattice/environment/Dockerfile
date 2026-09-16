# kedge-lattice: build the real libvips C image library at trial time.
# The checkout in /app/src is deliberately NOT built in this image: building
# and installing the project IS the task. A clean meson+ninja build at one
# CPU takes about 90 seconds (measured), so leaving it to the agent is the
# whole point of the task (TB2.1's opencv/opencv build-task substitute).
FROM bench-base:ubuntu-24.04

WORKDIR /app

# Toolchain and library dependencies for libvips 8.18.6. apt packages are
# intentionally not version-pinned: Debian rotates its archives, and the
# trial runs offline so nothing is fetched at trial time.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    git ninja-build meson pkg-config build-essential binutils file \
    libglib2.0-dev libexpat1-dev libjpeg-dev libpng-dev libtiff-dev \
    libwebp-dev liblcms2-dev libfftw3-dev \
 && rm -rf /var/lib/apt/lists/*

# Pinned upstream checkout. A tag alone is not a pin: a force-moved tag
# upstream would silently change what the trial builds, so we assert the
# full 40-hex commit before allowing the build to continue.
ARG UPSTREAM_SHA=426af3f44246fce9cfa8dd51a353aa4dfd48c553
RUN git clone --depth 1 --branch v8.18.6 \
        https://github.com/libvips/libvips.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# The trial runs on one CPU; pin numeric thread pools to 1.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

COPY files/ /app/