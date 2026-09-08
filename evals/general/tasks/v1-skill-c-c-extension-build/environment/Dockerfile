FROM bench-base:python-3.12

WORKDIR /app

# g++ and the C dev headers for building a CPython C++ extension + C CLI.
RUN apt-get update && apt-get install -y gcc g++ libc6-dev && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --upgrade pip==26.2.1 setuptools==84.0.0

# C/C++ sources for the quickcalc extension and the calc_cli tool.
COPY files/native/ /app/native/