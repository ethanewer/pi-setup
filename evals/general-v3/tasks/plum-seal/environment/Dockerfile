FROM bench-base:python-3.12

# openssl for certificate generation; the cryptography library for exact
# PEM parsing / cert building (no runtime network needed after install).
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir "cryptography>=41"

WORKDIR /app

COPY files/ /app/
