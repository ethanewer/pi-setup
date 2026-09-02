FROM bench-base:python-3.12

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential \
    >/dev/null && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir numpy >/dev/null 2>&1

WORKDIR /app

COPY files/ /app/