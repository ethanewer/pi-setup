FROM bench-base:ubuntu-24.04

WORKDIR /app

# Forensics toolkit: python3 (bench-base), plus hexdump/strings conveniences.
RUN apt-get update && apt-get install -y binutils && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workspace
COPY files/make_case.py /workspace/make_case.py
RUN python3 /workspace/make_case.py