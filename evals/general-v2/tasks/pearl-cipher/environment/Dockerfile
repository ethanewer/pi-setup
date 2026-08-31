FROM bench-base:python-3.12

# numpy for the bulk cipher search; gcc as an alternative compiled-search path.
RUN python3 -m pip install --no-cache-dir numpy >/dev/null 2>&1 && \
    python3 -c "import numpy; print('numpy', numpy.__version__)" && \
    (command -v gcc >/dev/null || apt-get update >/dev/null 2>&1 && \
     DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       gcc >/dev/null 2>&1 && rm -rf /var/lib/apt/lists/* || true)

WORKDIR /app

COPY files/ /app/
