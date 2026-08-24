FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y make && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/config.mk files/build.py files/Makefile /app/pkg/