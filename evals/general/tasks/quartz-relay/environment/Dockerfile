FROM bench-base:python-3.12

WORKDIR /app

# Headless vim is the tooling under test; python3 ships with the base image.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim \
    && rm -rf /var/lib/apt/lists/* \
    && vim --version | head -1

COPY files/ /app/
