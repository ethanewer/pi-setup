FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- toolchain: compilers + python headers (offline after this)
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        build-essential \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- python layer: numpy 2.x runtime, cython, pytest
RUN pip install -q \
        "numpy>=2.0" \
        "cython<3.1" \
        setuptools \
        pytest

# ---- the (unported) hexcore source tree; nothing is pre-built or installed
WORKDIR /app

COPY files/ /app/
