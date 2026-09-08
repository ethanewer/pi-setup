FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql \
    postgresql-client \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir --break-system-packages \
    grpcio==1.83.1 grpcio-tools==1.83.1 protobuf==7.36.1

WORKDIR /app
COPY files/ /app/