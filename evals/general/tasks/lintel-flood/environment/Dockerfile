FROM bench-base:ubuntu-24.04

# Rust 1.75 toolchain (verified available in the noble apt archive) plus a C
# linker, which cargo needs to link the test executables.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        rustc \
        cargo \
        gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/

CMD ["/bin/bash"]