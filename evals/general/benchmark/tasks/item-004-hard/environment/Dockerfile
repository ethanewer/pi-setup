FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev g++ libc6-dev make && rm -rf /var/lib/apt/lists/*

RUN pip install --disable-pip-version-check numpy cython setuptools wheel

COPY files/workbench /app/workbench