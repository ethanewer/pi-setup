FROM bench-base:ubuntu-24.04
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 nodejs vim xxd \
  && rm -rf /var/lib/apt/lists/*
COPY files/ /app/
# Generate the wasm fixtures (the exported-function -> memory-offset module and a
# deliberately malformed binary used by the hidden malformed-input case).
RUN python3 /app/data/make_wasm.py && rm /app/data/make_wasm.py