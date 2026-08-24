FROM bench-base:python-3.12

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
RUN pip install --disable-pip-version-check numpy setuptools

WORKDIR /app

COPY files/prices.csv /app/prices.csv