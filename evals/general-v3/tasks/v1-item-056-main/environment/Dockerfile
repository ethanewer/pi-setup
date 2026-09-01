FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev make \
    && rm -rf /var/lib/apt/lists/*

RUN pip install numpy setuptools

COPY files/ /app/
RUN mkdir -p /app/out