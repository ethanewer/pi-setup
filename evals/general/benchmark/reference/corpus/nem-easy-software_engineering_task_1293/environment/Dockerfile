# Software Engineering Dockerfile
# General development environment

FROM ghcr.io/laude-institute/t-bench/ubuntu-24-04:latest

# Install system packages
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3-pip \
    build-essential \
    pkg-config \
    git \
    curl \
    wget \
    jq \
    cmake \
    make \
    gcc \
    g++ \
    clang \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install Python packages
RUN pip3 install --no-cache-dir --break-system-packages \
    requests \
    flask \
    fastapi \
    uvicorn \
    sqlalchemy \
    pytest \
    black \
    mypy \
    pyyaml \
    toml

WORKDIR /app
COPY files/ /app/