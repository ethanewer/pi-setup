FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# rustc/cargo 1.75 from Ubuntu noble; the crate must stay zero-dependency so
# that `cargo test` works with no network at trial time.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        rustc \
        cargo \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/

# Toolchain sanity + fixture compiles (the crate's test suite is intentionally
# red until the task is solved, so only `cargo build` runs at image time).
RUN cd /app/lwrecord && cargo build --offline

CMD ["/bin/bash"]
