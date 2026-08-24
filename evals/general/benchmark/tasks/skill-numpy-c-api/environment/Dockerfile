FROM bench-base:python-3.12

WORKDIR /app

# C compiler toolchain for building the C extension.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev g++ libc6-dev make && rm -rf /var/lib/apt/lists/*

# NumPy headers + build tools.
RUN pip install --disable-pip-version-check numpy setuptools wheel