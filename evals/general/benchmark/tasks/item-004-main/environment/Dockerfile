FROM bench-base:python-3.12

WORKDIR /app

# C compiler toolchain for building the Cython/C extension.
RUN apt-get update && apt-get install -y gcc libc6-dev g++ libc6-dev make && rm -rf /var/lib/apt/lists/*

# Numeric + build toolchain for Cython.
RUN pip install --disable-pip-version-check numpy cython setuptools wheel

# Ship the legacy package source under /app/workbench.
COPY files/workbench /app/workbench