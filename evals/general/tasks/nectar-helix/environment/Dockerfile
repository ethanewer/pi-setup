FROM bench-base:ubuntu-24.04

# Tooling for the three file-tree utilities. findutils (find/xargs) and file
# are present for convenience; python3 is the canonical runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv file findutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/