# Data Querying Dockerfile
# Database clients and query tools

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
    sqlite3 \
    postgresql-client \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install Python packages
RUN pip3 install --no-cache-dir --break-system-packages \
    numpy \
    pandas \
    sqlalchemy \
    psycopg2-binary \
    pymysql \
    duckdb \
    requests \
    pyyaml

WORKDIR /app
COPY files/ /app/