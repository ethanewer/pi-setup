FROM bench-base:ubuntu-24.04

# gcc: compile the C preprocessor-trick program.
RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app