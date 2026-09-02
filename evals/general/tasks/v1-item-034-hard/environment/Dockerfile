FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && \
    apt-get install -y nginx && \
    rm -rf /var/lib/apt/lists/*

COPY files/ /app/