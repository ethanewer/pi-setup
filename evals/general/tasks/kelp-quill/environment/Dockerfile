FROM bench-base:python-3.12

# openssl CLI for provisioning convenience; cryptography for exact PEM parsing
# (installed at build time; fully offline at run/verify).
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/* \
    && pip install -q "cryptography>=41"

WORKDIR /app

COPY files/ /app/
