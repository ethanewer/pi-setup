FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# toolchain: compiler + python headers for building the extension
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# the NEW numpy the vendored package must be ported to (no numpy 1.x present)
RUN pip install -q "numpy>=2.0,<3" "cython>=3.0,<4" setuptools

# vendored sources in their broken (numpy 1.x era) state
COPY files/ /app/

WORKDIR /app
