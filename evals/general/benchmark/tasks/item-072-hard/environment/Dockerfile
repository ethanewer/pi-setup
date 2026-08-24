FROM bench-base:python-3.12

WORKDIR /app

# C++ toolchain needed to build the fasttext Python wheel from source.
RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# fasttext 0.9.2 releases a macOS-only binary wheel; the sdist builds from
# source here. Its 0.9.2 Python wrapper is incompatible with numpy>=2
# (ValueError "Unable to avoid copy..."), so pin numpy<2.
RUN pip install --no-cache-dir "numpy<2" pandas pyarrow fasttext

# Review data (train/val, parquet) used by the task.
COPY files/ /app/data/
RUN mkdir -p /app/output