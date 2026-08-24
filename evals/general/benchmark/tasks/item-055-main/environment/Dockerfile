FROM bench-base:ubuntu-24.04

WORKDIR /app

# gcc/g++ for the C-family modes; rustc via apt if available, else rustup fallback.
RUN apt-get update \
 && (apt-get install -y --no-install-recommends gcc g++ libc6-dev libc6-dev || true) \
 && (apt-get install -y --no-install-recommends rustc curl || true) \
 && rm -rf /var/lib/apt/lists/*

RUN if ! command -v rustc >/dev/null 2>&1; then \
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal; \
      ln -sf "$HOME/.cargo/bin/rustc" /usr/local/bin/rustc; \
      ln -sf "$HOME/.cargo/bin/rustdoc" /usr/local/bin/rustdoc; \
    fi

COPY files/ /app/polyglot/