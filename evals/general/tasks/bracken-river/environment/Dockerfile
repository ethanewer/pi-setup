FROM bench-base:ubuntu-24.04

# Air-gapped R-runtime bootstrap bench for bracken-river.
# Build stage only: python3 for the pipeline launcher, then a one-time
# download of the complete r-base-core dependency closure into /app/debs
# WITHOUT installing it. The agent installs R offline from that bundle.
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && mkdir -p /app/debs \
    && apt-get install -y --download-only --no-install-recommends r-base-core \
    && cp -a /var/cache/apt/archives/*.deb /app/debs/ \
    && rm -rf /var/cache/apt/archives/*.deb /var/lib/apt/lists/* \
    && ls /app/debs/*.deb | wc -l

WORKDIR /app

COPY files/ /app/
COPY files/pipeline/sampler.R /opt/pristine/sampler.R
COPY files/pipeline/riverlaunch.py /opt/pristine/riverlaunch.py
COPY files/pipeline/params_visible.txt /opt/pristine/params_visible.txt
