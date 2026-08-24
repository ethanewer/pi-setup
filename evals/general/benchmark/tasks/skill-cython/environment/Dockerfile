FROM bench-base:python-3.12

WORKDIR /app

# C compiler toolchain for building the Cython extension.
RUN apt-get update && apt-get install -y gcc libc6-dev g++ libc6-dev make && rm -rf /var/lib/apt/lists/*

# Cython + packaging toolchain.
RUN pip install --disable-pip-version-check cython setuptools wheel

# A tiny Cython module that the agent must compile into an extension.
COPY files/math /app/math