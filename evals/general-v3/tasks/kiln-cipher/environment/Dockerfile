FROM bench-base:python-3.12

WORKDIR /app

# openssl CLI for certificate generation.
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/*

# Staging spec for the visible identity.
COPY files/ /app/
