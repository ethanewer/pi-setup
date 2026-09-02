FROM bench-base:python-3.12

WORKDIR /app

# The task rebuilds a CPython C extension from source, so it needs a C
# toolchain, Python development headers, and setuptools.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir setuptools

COPY files/ /app/